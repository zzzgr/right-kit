import Foundation
import XCTest
@testable import RightKitShared

final class MarketProtocolTests: XCTestCase {
    private let origin = URL(string: "https://market.example.com")!

    func testImportLinksCarryOriginAndHashAndRejectAmbiguousOrForeignSources() throws {
        let digest = String(repeating: "a", count: 64)
        var components = URLComponents(string: "rightkit://import")!
        components.queryItems = [
            URLQueryItem(name: "url", value: origin.appendingPathComponent("actions/one/1.0.0.json").absoluteString),
            URLQueryItem(name: "market", value: origin.absoluteString),
            URLQueryItem(name: "sha256", value: digest)
        ]
        let link = try MarketLink.parse(components.url!)
        XCTAssertEqual(link.kind, .importAction)
        XCTAssertEqual(link.marketURL?.path, "/.well-known/rightkit-market.json")
        XCTAssertEqual(link.sha256, digest)
        components.queryItems?.append(URLQueryItem(name: "url", value: origin.absoluteString))
        XCTAssertThrowsError(try MarketLink.parse(components.url!))
        components.queryItems?.removeLast()
        components.queryItems?[1].value = "https://different.example.com"
        XCTAssertThrowsError(try MarketLink.parse(components.url!))
        XCTAssertNoThrow(try MarketLink.parse(URL(string: "rightkit://import?url=https%3A%2F%2Fmarket.example.com%2Fone.json")!))
        XCTAssertThrowsError(try MarketLink.parse(URL(string: "rightkit://market?url=https%3A%2F%2Fmarket.example.com&sha256=abc")!))
    }

    func testHTTPAndHTTPSMarketsAcceptLocalAndRemoteAddresses() throws {
        for raw in ["http://localhost:3000", "http://127.0.0.1:3000", "http://[::1]:3000", "http://192.168.1.2:3000", "http://market.example.com", "https://market.example.com"] {
            let url = URL(string: raw)!
            XCTAssertNoThrow(try MarketProtocol.validateURL(url))
            XCTAssertEqual(try MarketProtocol.catalogURL(raw).path, "/.well-known/rightkit-market.json")
            if url.scheme == "http" {
                XCTAssertThrowsError(try MarketProtocol.validateURL(url, allowHTTP: false)) {
                    XCTAssertEqual($0 as? MarketCatalogError, .httpsRequired)
                }
            }
        }
        for raw in ["file:///tmp/catalog.json", "ftp://example.com/catalog.json", "http://user:pass@example.com", "http://example.com/#fragment", "https://user:pass@example.com", "https://example.com/#fragment"] {
            XCTAssertThrowsError(try MarketProtocol.validateURL(URL(string: raw)!))
        }
        XCTAssertEqual(try MarketProtocol.catalogURL("HTTPS://MARKET.EXAMPLE.COM:443/"), try MarketProtocol.catalogURL(origin.absoluteString))
        XCTAssertEqual(try MarketProtocol.catalogURL("HTTP://MARKET.EXAMPLE.COM:80/"), try MarketProtocol.catalogURL("http://market.example.com"))
        XCTAssertEqual(try MarketProtocol.catalogURL("https://market.example.com/catalog.json?channel=stable").query, "channel=stable")
    }

    func testInstalledClientLinksAcceptHTTPMarketsAndExplainInvalidAddresses() throws {
        for raw in ["http://127.0.0.1:3000", "http://localhost:3000", "http://[::1]:3000", "http://192.168.1.2:3000", "http://market.example.com"] {
            var subscription = URLComponents(string: "rightkit://market")!
            subscription.queryItems = [URLQueryItem(name: "url", value: raw)]
            XCTAssertEqual(try MarketLink.parse(subscription.url!).kind, .market)

            var action = URLComponents(string: "rightkit://import")!
            action.queryItems = [
                URLQueryItem(name: "url", value: raw + "/rightkit/actions/example/1.0.0.json"),
                URLQueryItem(name: "market", value: raw),
                URLQueryItem(name: "sha256", value: String(repeating: "a", count: 64))
            ]
            let link = try MarketLink.parse(action.url!)
            XCTAssertEqual(link.kind, .importAction)
            XCTAssertEqual(link.marketURL?.path, "/.well-known/rightkit-market.json")
            XCTAssertEqual(link.url.lastPathComponent, "1.0.0.json")
        }
        for raw in ["file:///tmp/catalog.json", "ftp://example.com/catalog.json", "http://user:pass@example.com"] {
            var components = URLComponents(string: "rightkit://market")!
            components.queryItems = [URLQueryItem(name: "url", value: raw)]
            XCTAssertThrowsError(try MarketLink.parse(components.url!)) {
                XCTAssertEqual($0 as? MarketCatalogError, .invalidURL)
            }
        }
        XCTAssertThrowsError(try MarketProtocol.catalogURL("not a market URL")) {
            XCTAssertEqual($0 as? MarketCatalogError, .invalidURL)
        }
        XCTAssertThrowsError(try MarketLink.parse(URL(string: "rightkit://import")!)) {
            XCTAssertEqual($0 as? MarketCatalogError, .invalidLink)
        }
    }

    func testHTTPStillRequiresMatchingProtocolHostAndPort() throws {
        let origin = URL(string: "http://192.168.1.2:3000")!
        XCTAssertNoThrow(try MarketProtocol.validateURL(origin.appendingPathComponent("package.json"), relativeTo: origin))
        for raw in ["http://192.168.1.3:3000/package.json", "http://192.168.1.2:3001/package.json", "https://192.168.1.2:3000/package.json"] {
            XCTAssertThrowsError(try MarketProtocol.validateURL(URL(string: raw)!, relativeTo: origin)) {
                XCTAssertEqual($0 as? MarketCatalogError, .invalid)
            }
        }
        XCTAssertNoThrow(try MarketProtocol.validateURL(URL(string: "HTTP://MARKET.EXAMPLE.COM:80/file.json")!, relativeTo: URL(string: "http://market.example.com")!))
    }

    func testHTTPMarketUpdateIdentityRemainsBoundToItsAddress() throws {
        let origin = URL(string: "http://192.168.1.2:3000")!
        let metadata = CustomAction.PackageMetadata(id: "one", version: "1.0.0", source: .market, marketURL: origin)
        XCTAssertTrue(ActionPackageUpdate.matches(metadata, packageID: "one", source: .market,
                                                 marketURL: try MarketProtocol.catalogURL(origin.absoluteString), sourceURL: nil))
        XCTAssertFalse(ActionPackageUpdate.matches(metadata, packageID: "one", source: .market,
                                                  marketURL: URL(string: "http://192.168.1.3:3000"), sourceURL: nil))
    }

    func testBothTimestampFormatsAndSemanticVersionOrdering() throws {
        let fractional = try MarketProtocol.decoder.decode(Date.self, from: Data("\"2026-09-08T00:00:00.123Z\"".utf8))
        let ordinary = try MarketProtocol.decoder.decode(Date.self, from: Data("\"2026-09-08T00:00:00Z\"".utf8))
        XCTAssertEqual(fractional.timeIntervalSince(ordinary), 0.123, accuracy: 0.001)
        XCTAssertTrue(MarketProtocol.isNewer("1.10.0", than: "1.9.0"))
        XCTAssertTrue(MarketProtocol.isNewer("2.0.0", than: "2.0.0-beta.2"))
        XCTAssertFalse(MarketProtocol.isNewer("2.0.0-beta.2", than: "2.0.0-beta.10"))
        XCTAssertFalse(MarketProtocol.isNewer("1.0.0+build.2", than: "1.0.0+build.1"))
    }

    func testUpdateIdentityUsesMarketAndStableIDAndExcludesDetachedCopies() throws {
        var metadata = CustomAction.PackageMetadata(id: "one", version: "1.0.0", source: .market, marketURL: origin)
        let canonical = try MarketProtocol.catalogURL(origin.absoluteString)
        XCTAssertTrue(ActionPackageUpdate.matches(metadata, packageID: "one", source: .market, marketURL: canonical, sourceURL: nil))
        XCTAssertFalse(ActionPackageUpdate.matches(metadata, packageID: "one", source: .market, marketURL: URL(string: "https://another.example.com"), sourceURL: nil))
        XCTAssertFalse(ActionPackageUpdate.matches(metadata, packageID: "two", source: .market, marketURL: origin, sourceURL: nil))
        metadata.tracksUpdates = false
        XCTAssertFalse(ActionPackageUpdate.matches(metadata, packageID: "one", source: .market, marketURL: origin, sourceURL: nil))
        metadata.tracksUpdates = nil
        metadata.marketURL = URL(string: "file:///tmp")
        XCTAssertFalse(ActionPackageUpdate.matches(metadata, packageID: "one", source: .market, marketURL: URL(string: "file:///tmp"), sourceURL: nil))
    }

    func testThreeWayMergePreservesLocalRuntimeSecretsAndUncontestedEdits() throws {
        var original = CustomAction()
        original.title = "Original"; original.script = "print('original')"
        original.environment = [ScriptEnvironmentVariable(name: "TOKEN", value: "", isSecret: true), ScriptEnvironmentVariable(name: "OUTPUT", value: "default", isSecret: false)]
        let baseline = try ActionPackageExporter.make(from: original, packageID: "one")
        var local = try baseline.makeCustomAction()
        local.packageMetadata = .init(id: "one", version: "1.0.0", source: .market, marketURL: origin)
        local.packageMetadata?.baseline = baseline
        local.script = "print('local')"; local.isEnabled = false
        local.interpreterPath = "/local/venv/bin/python"
        local.customWorkingDirectory = "/local/output"
        local.environment[1].value = "local-output"
        var remote = baseline
        remote.version = "1.1.0"; remote.action.title = "Remote title"
        let merged = ActionPackageUpdate.merge(try remote.makeCustomAction(), with: local, package: remote, preferLocal: false)
        XCTAssertEqual(merged.id, local.id)
        XCTAssertEqual(merged.title, "Remote title")
        XCTAssertEqual(merged.script, local.script)
        XCTAssertFalse(merged.isEnabled)
        XCTAssertEqual(merged.interpreterPath, local.interpreterPath)
        XCTAssertEqual(merged.customWorkingDirectory, local.customWorkingDirectory)
        XCTAssertEqual(merged.environment[0].id, local.environment[0].id)
        XCTAssertEqual(merged.environment[1].value, "local-output")
        remote.action.script.content = "print('remote')"
        let incoming = try remote.makeCustomAction()
        XCTAssertEqual(ActionPackageUpdate.merge(incoming, with: local, package: remote, preferLocal: true).script, local.script)
        XCTAssertEqual(ActionPackageUpdate.merge(incoming, with: local, package: remote, preferLocal: false).script, remote.action.script.content)
    }

    func testCompatibilityBlocksNewerClientAndOSWithoutDependingOnOSLocale() throws {
        var action = CustomAction(); action.title = "One"; action.script = "echo one"
        var package = try ActionPackageExporter.make(from: action, packageID: "one")
        package.minRightKitVersion = "1.2.0"; package.minMacOSVersion = "13.0"
        XCTAssertNoThrow(try package.checkCompatibility(clientVersion: "1.2.0", macOSVersion: "13.0"))
        XCTAssertNoThrow(try package.checkCompatibility())
        XCTAssertThrowsError(try package.checkCompatibility(clientVersion: "1.1.0", macOSVersion: "13.0"))
        XCTAssertThrowsError(try package.checkCompatibility(clientVersion: "1.2.0", macOSVersion: "12.0"))
    }
}
