import Foundation
import XCTest
@testable import RightKitShared

final class MarketHTTPClientTests: XCTestCase {
    func testConfiguredMarketInteroperability() async throws {
        guard let raw = ProcessInfo.processInfo.environment["MARKET_INTEGRATION_URL"], let url = URL(string: raw) else {
            throw XCTSkip("Set MARKET_INTEGRATION_URL to validate a running web market")
        }
        let client = MarketHTTPClient()
        let snapshot = try await client.catalog(url)
        XCTAssertFalse(snapshot.items.isEmpty)
        for item in snapshot.items {
            let (package, hash) = try await client.package(item.packageURL, origin: url, expected: item)
            XCTAssertEqual(package.id, item.id)
            XCTAssertEqual(hash, item.sha256)
            if let iconURL = item.iconURL {
                let data = try await client.icon(item, origin: url)
                XCTAssertNotNil(data)
                XCTAssertEqual(iconURL.host, url.host)
            }
            if let versionsURL = item.versionsURL {
                let history = try await client.versions(versionsURL, packageID: item.id, origin: url)
                XCTAssertEqual(history.versions.first?.version, item.version)
                XCTAssertEqual(history.versions.first?.sha256, item.sha256)
            }
        }
    }

    func testFetchesEveryPageAndReusesETagSnapshot() async throws {
        let server = try LocalMarketServer()
        let client = MarketHTTPClient()
        let snapshot = try await client.catalog(server.url("/first.json"))
        XCTAssertEqual(snapshot.items.map(\.id), ["one", "two"])
        XCTAssertEqual(snapshot.pages.count, 2)
        XCTAssertEqual(snapshot.etag, "\"fixture-v1\"")
        let cached = try await client.catalog(server.url("/first.json"), cached: snapshot)
        XCTAssertEqual(cached, snapshot)
    }

    func testLoadsOnlyOnePageAndNeverReusesAnotherQuerysETag() async throws {
        let server = try LocalMarketServer()
        let client = MarketHTTPClient()
        let first = try await client.catalogPage(server.url("/first.json?q=one"))
        XCTAssertEqual(first.catalog.items.map(\.id), ["one"])
        XCTAssertNotNil(first.catalog.next)
        let same = try await client.catalogPage(first.url, cached: first)
        XCTAssertEqual(same, first)
        let otherURL = server.url("/first.json?q=two")
        let other = try await client.catalogPage(otherURL, cached: first)
        XCTAssertEqual(other.url, otherURL)
        let cycle = try await client.catalogPage(server.url("/cycle.json"))
        XCTAssertEqual(cycle.catalog.items.count, 1, "Single-page loading must not follow next")
    }

    func testPagedCatalogHandlesTwentyItemsAndGlobalSearch() async throws {
        let server = try LocalMarketServer()
        let client = MarketHTTPClient()
        let url = server.url("/paged.json")
        let first = try await client.catalogPage(url)
        XCTAssertEqual(first.catalog.items.count, 20)
        XCTAssertEqual(first.catalog.pagination, MarketPagination(total: 43))
        let second = try await client.catalogPage(try XCTUnwrap(first.catalog.next))
        let third = try await client.catalogPage(try XCTUnwrap(second.catalog.next))
        XCTAssertEqual(second.catalog.items.count, 20)
        XCTAssertEqual(third.catalog.items.count, 3)
        XCTAssertNil(third.catalog.next)
        XCTAssertThrowsError(try MarketSnapshot(pages: [third.catalog]).validate(origin: url), "The final page alone is not a complete catalog")
        XCTAssertEqual(Set((first.catalog.items + second.catalog.items + third.catalog.items).map(\.id)).count, 43)
        let filtered = try await client.catalogPage(MarketQuery(search: "Item 42").url(for: url))
        XCTAssertEqual(filtered.catalog.items.map(\.title), ["Item 42"])
        XCTAssertEqual(filtered.catalog.pagination?.total, 1)
        let all = try await client.catalog(url)
        XCTAssertEqual(all.items.count, 43)
    }

    func testPackageHashIdentityAndSameOriginRedirect() async throws {
        let server = try LocalMarketServer()
        let client = MarketHTTPClient(allowHTTP: true)
        let snapshot = try await client.catalog(server.url("/first.json"))
        var item = try XCTUnwrap(snapshot.items.first)
        let (package, hash) = try await client.package(item.packageURL, origin: server.origin, expected: item)
        XCTAssertEqual(package.id, "one")
        XCTAssertEqual(hash, item.sha256)
        let (redirected, _) = try await client.package(server.url("/redirect.json"), origin: server.origin, expected: item)
        XCTAssertEqual(redirected, package)
        item.sha256 = String(repeating: "0", count: 64)
        do { _ = try await client.package(item.packageURL, origin: server.origin, expected: item); XCTFail("Accepted wrong hash") }
        catch { XCTAssertEqual(error as? MarketCatalogError, .hashMismatch) }
        item.sha256 = hash; item.id = "wrong-id"
        do { _ = try await client.package(item.packageURL, origin: server.origin, expected: item); XCTFail("Accepted wrong ID") }
        catch { XCTAssertEqual(error as? MarketCatalogError, .invalid) }
    }

    func testRejectsPaginationLoopsCrossOriginAndMixedSnapshots() async throws {
        let server = try LocalMarketServer()
        let client = MarketHTTPClient(allowHTTP: true)
        for path in ["/cycle.json", "/foreign-page.json", "/duplicate.json", "/drift.json"] {
            do { _ = try await client.catalog(server.url(path)); XCTFail("Accepted invalid catalog: \(path)") }
            catch { XCTAssertEqual(error as? MarketCatalogError, .invalid) }
        }
        do { _ = try await client.package(server.url("/foreign-redirect.json")); XCTFail("Followed foreign redirect") }
        catch { XCTAssertEqual(error as? MarketCatalogError, .invalid) }
    }

    func testBoundsContentLengthAndStreamAndLoadsReleaseNotes() async throws {
        let server = try LocalMarketServer()
        let client = MarketHTTPClient(allowHTTP: true)
        for path in ["/large.json", "/stream.json"] {
            do { _ = try await client.get(server.url(path), origin: server.origin, limit: 128); XCTFail("Accepted oversized response") }
            catch { XCTAssertTrue(error is MarketCatalogError || error is ActionPackageError || error is URLError, "Unexpected transport error: \(error)") }
        }
        let versions = try await client.versions(server.url("/versions.json"), packageID: "one", origin: server.origin)
        XCTAssertEqual(versions.versions.first?.notes, "SVG icon and first release")
        XCTAssertEqual(versions.versions.first?.sha256, MarketProtocol.hash(server.packageData))
        do { _ = try await client.versions(server.url("/versions.json"), packageID: "different", origin: server.origin); XCTFail("Accepted another action's notes") }
        catch { XCTAssertEqual(error as? MarketCatalogError, .invalid) }
    }
}

private final class LocalMarketServer {
    let process = Process()
    let origin: URL
    let packageData: Data

    init() throws {
        var action = CustomAction(); action.title = "One"; action.script = "print('preview only')"
        packageData = try ActionPackageExporter.make(from: action, packageID: "one").encodedData()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", Self.script, packageData.base64EncodedString()]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        var line = Data()
        while !line.contains(10) {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { process.terminate(); throw MarketCatalogError.offline }
            line.append(chunk)
        }
        guard let port = Int(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
              let url = URL(string: "http://127.0.0.1:\(port)") else { process.terminate(); throw MarketCatalogError.offline }
        origin = url
    }
    deinit { if process.isRunning { process.terminate(); process.waitUntilExit() } }
    func url(_ path: String) -> URL { URL(string: path, relativeTo: origin)!.absoluteURL }

    private static let script = #"""
import base64, hashlib, json, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, urlencode
package = base64.b64decode(sys.argv[1])
sha = hashlib.sha256(package).hexdigest()
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        base = 'http://127.0.0.1:' + str(self.server.server_port)
        path = urlparse(self.path).path
        if path in ['/redirect.json', '/foreign-redirect.json']:
            self.send_response(302)
            self.send_header('Location', base + '/package.json' if path == '/redirect.json' else 'https://different.invalid/package.json')
            self.end_headers(); return
        if path == '/first.json' and self.headers.get('If-None-Match') == '"fixture-v1"':
            self.send_response(304); self.end_headers(); return
        if path == '/large.json':
            self.send_response(200); self.send_header('Content-Length', '9999999'); self.end_headers(); return
        if path == '/stream.json':
            self.send_response(200); self.end_headers(); self.wfile.write(b'x' * 1024); return
        item = dict(id='two' if path in ['/second.json', '/changed.json'] else 'one', version='1.0.0', title='One', summary='A fixture', language='python', target='files', tags=[], symbol='terminal', packageURL=base+'/package.json', sha256=sha, updatedAt='2026-09-08T00:00:00.123Z', versionsURL=base+'/versions.json', detailURL=base+'/actions/one')
        next = None
        if path in ['/first.json', '/duplicate.json']: next = base + ('/second.json' if path == '/first.json' else '/one-again.json')
        if path == '/drift.json': next = base + '/changed.json'
        if path == '/cycle.json': next = base + '/cycle.json'
        if path == '/foreign-page.json': next = 'https://different.invalid/page.json'
        catalog = dict(format='rightkit.market', schemaVersion=1, id='fixture', name='Fixture', homepage=base, generatedAt='2026-09-09T00:00:00Z' if path == '/changed.json' else '2026-09-08T00:00:00.000Z', items=[item], next=next)
        if path == '/paged.json':
            params = parse_qs(urlparse(self.path).query)
            size = int(params.get('pageSize', ['20'])[0])
            search = params.get('q', [''])[0].lower()
            items = [dict(item, id='item-' + str(i), title='Item ' + str(i)) for i in range(43) if search in ('Item ' + str(i)).lower()]
            total_pages = max(1, (len(items) + size - 1) // size)
            page = min(total_pages, int(params.get('page', ['1'])[0]))
            catalog['items'] = items[(page - 1) * size:page * size]
            catalog['pagination'] = dict(page=page, pageSize=size, total=len(items), totalPages=total_pages)
            if page < total_pages:
                params['page'] = [str(page + 1)]
                catalog['next'] = base + '/paged.json?' + urlencode(params, doseq=True)
        body = package if path == '/package.json' else json.dumps(catalog).encode()
        if path == '/versions.json':
            body = json.dumps(dict(format='rightkit.versions', schemaVersion=1, id='one', versions=[dict(version='1.0.0', notes='SVG icon and first release', sha256=sha, createdAt='2026-09-08T00:00:00.123Z', packageURL=base+'/package.json')], next=None)).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('ETag', '"fixture-v1"')
        self.end_headers()
        self.wfile.write(body)
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
"""#
}
