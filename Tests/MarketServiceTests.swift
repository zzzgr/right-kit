import Foundation
import RightKitShared
import XCTest

final class MarketServiceTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RightKitMarketTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func snapshot(_ url: URL) -> MarketCatalogPage {
        let item = MarketCatalog.Item(id: "action", version: "1.0.0", title: "Action", summary: "Test action",
                                      language: .python, target: .files, tags: [], symbol: "terminal",
                                      packageURL: url.deletingLastPathComponent().appendingPathComponent("action.json"),
                                      sha256: String(repeating: "a", count: 64), updatedAt: Date(timeIntervalSince1970: 1))
        return MarketCatalogPage(url: url, catalog: MarketCatalog(id: "fixture", name: url.host!, homepage: url,
                                                  generatedAt: Date(timeIntervalSince1970: 1), items: [item]))
    }

    private static func paged(_ url: URL) throws -> MarketCatalogPage {
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? { params.first(where: { $0.name == key })?.value }
        let query = MarketQuery(page: Int(value("page") ?? "1")!, pageSize: Int(value("pageSize") ?? "20")!,
                                search: value("q") ?? "", language: value("language") ?? "all",
                                ids: value("ids").map { $0.split(separator: ",").map(String.init) })
        let all = (0..<43).map { index in
            var item = snapshot(url).catalog.items[0]
            item.id = String(format: "item-%02d", index); item.title = "Item \(index)"
            item.language = index.isMultiple(of: 2) ? .python : .bash
            item.version = "1.1.0"
            return item
        }.filter(query.matches)
        let pagination = MarketPagination(total: all.count, page: query.page, pageSize: query.pageSize)
        var catalog = snapshot(url).catalog
        catalog.homepage = URL(string: "https://market.example.com")!
        catalog.pagination = pagination
        catalog.items = Array(all.dropFirst((pagination.page - 1) * pagination.pageSize).prefix(pagination.pageSize))
        if pagination.page < pagination.totalPages {
            var next = query; next.page = pagination.page + 1
            catalog.next = try next.url(for: url)
        }
        return MarketCatalogPage(url: url, catalog: catalog, etag: "\"\(url.absoluteString)\"")
    }

    @MainActor
    func testBrowsingLoadsOnlyRequestedPagesAndSearchesBeyondTheFirstPage() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var requests: [URL] = []
        let service = MarketService(root: root) { url, _ in requests.append(url); return try Self.paged(url) }
        try await service.saveSource("https://market.example.com")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(service.items().count, 20)
        XCTAssertEqual(service.pagination.total, 43)
        await service.browse(MarketQuery(page: 2))
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(service.items().first?.item.id, "item-20")
        await service.browse(MarketQuery(page: 3))
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(service.items().count, 3)
        await service.browse(MarketQuery(search: "Item 42"))
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(service.items().map(\.item.id), ["item-42"])
        XCTAssertEqual(service.pagination.total, 1)
        XCTAssertEqual(MarketService(root: root).items().first?.item.id, "item-00", "A search must not replace the default persisted cache")
        await service.browse(MarketQuery(page: 99, language: "python"))
        XCTAssertEqual(service.pagination, MarketPagination(total: 22, page: 2))
        XCTAssertEqual(service.items().map(\.item.id), ["item-40", "item-42"])
    }

    @MainActor
    func testUpdatesOnlyQueriesTrackedIDsIncludingActionsBeyondPageOne() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var requests: [URL] = []
        let service = MarketService(root: root) { url, _ in requests.append(url); return try Self.paged(url) }
        try await service.saveSource("https://market.example.com")
        let origin = service.source!.url
        let installed = [MarketInstalledAction(id: "item-42", version: "1.0.0", marketURL: origin),
                         MarketInstalledAction(id: "item-41", version: "1.1.0", marketURL: origin),
                         MarketInstalledAction(id: "item-01", version: "1.0.0", marketURL: URL(string: "https://other.example.com")!)]
        await service.browse(MarketQuery(), installed: installed)
        XCTAssertEqual(requests.count, 2)
        let params = URLComponents(url: requests.last!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(params.first(where: { $0.name == "ids" })?.value, "item-41,item-42")
        XCTAssertEqual(params.first(where: { $0.name == "pageSize" })?.value, "100")
        XCTAssertEqual(service.items().map(\.item.id), ["item-42"])
        XCTAssertEqual(service.pagination.total, 1)
        await service.browse(MarketQuery(), installed: [])
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(service.items().isEmpty)
    }

    @MainActor
    func testLateSearchCannotReplaceNewerPageOrReportItsError() async throws {
        for fails in [false, true] {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let pending = PendingCatalog()
            let service = MarketService(root: root) { url, _ in
                if url.query?.contains("page=2") == true { return try await pending.load() }
                return try Self.paged(url)
            }
            try await service.saveSource("https://market.example.com")
            let delayed = Task { await service.browse(MarketQuery(page: 2)) }
            await pending.waitUntilLoading()
            await service.browse(MarketQuery(search: "Item 42"))
            let oldURL = try MarketQuery(page: 2).url(for: service.source!.url)
            pending.finish(fails ? .failure(MarketCatalogError.offline) : .success(try Self.paged(oldURL)))
            await delayed.value
            XCTAssertEqual(service.items().map(\.item.id), ["item-42"])
            XCTAssertEqual(service.pagination.total, 1)
            XCTAssertNil(service.error)
            XCTAssertNil(service.source?.lastError)
            XCTAssertFalse(service.isRefreshing)
        }
    }

    @MainActor
    func testPageCacheIsBoundToTheQueryAndOfflinePagesDoNotShowUnrelatedResults() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var offline = false
        let service = MarketService(root: root) { url, cached in
            if let cached { XCTAssertEqual(cached.url, url) }
            if offline { throw MarketCatalogError.offline }
            return try Self.paged(url)
        }
        try await service.saveSource("https://market.example.com")
        await service.browse(MarketQuery(page: 2))
        offline = true
        await service.browse(MarketQuery(page: 2))
        XCTAssertEqual(service.items().first?.item.id, "item-20")
        XCTAssertNotNil(service.source?.lastError)
        await service.browse(MarketQuery(page: 3))
        XCTAssertTrue(service.items().isEmpty)
        XCTAssertNotNil(service.error)
    }

    @MainActor
    func testVerifiedEditPersistsAndReplacesCacheWithoutChangingSourceID() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var usedForeignCache = false
        let service = MarketService(root: root) { url, cached in
            if url.host == "new.example.com", cached != nil { usedForeignCache = true }
            return Self.snapshot(url)
        }
        let id = try await service.saveSource("https://old.example.com")
        let editedID = try await service.saveSource("https://new.example.com", replacing: id)
        XCTAssertEqual(editedID, id)
        XCTAssertFalse(usedForeignCache)
        XCTAssertEqual(service.sources.count, 1)
        XCTAssertEqual(service.sources[0].url, try MarketProtocol.catalogURL("https://new.example.com"))
        XCTAssertEqual(service.items().first?.source.name, "new.example.com")
        let reloaded = MarketService(root: root)
        XCTAssertEqual(reloaded.sources, service.sources)
        XCTAssertEqual(reloaded.catalogs, service.catalogs)
    }

    @MainActor
    func testFailedEditPreservesSourceAndCacheOnDisk() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MarketService(root: root) { url, _ in
            if url.host == "broken.example.com" { throw MarketCatalogError.offline }
            return Self.snapshot(url)
        }
        let id = try await service.saveSource("https://original.example.com")
        let sources = service.sources, catalogs = service.catalogs
        let disk = try Data(contentsOf: root.appendingPathComponent("sources.json"))
        do {
            try await service.saveSource("https://broken.example.com", replacing: id)
            XCTFail("Failed verification must not replace a saved source")
        } catch { XCTAssertEqual(error as? MarketCatalogError, .offline) }
        XCTAssertEqual(service.sources, sources)
        XCTAssertEqual(service.catalogs, catalogs)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("sources.json")), disk)
        XCTAssertEqual(MarketService(root: root).catalogs, catalogs)
    }

    @MainActor
    func testInvalidAddressesAreRejectedBeforeDownloading() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var requests = 0
        let service = MarketService(root: root) { url, _ in
            requests += 1
            return Self.snapshot(url)
        }
        let id = try await service.saveSource("https://one.example.com")
        for raw in ["not a URL", "ftp://remote.example.com", "http://user:pass@remote.example.com", "http://remote.example.com/#fragment"] {
            do {
                try await service.saveSource(raw, replacing: id)
                XCTFail("Invalid address accepted: \(raw)")
            } catch { }
        }
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(service.sources.count, 1)
        XCTAssertEqual(service.sources.first?.url.host, "one.example.com")
    }

    @MainActor
    func testSavingAnotherAddressReplacesTheOnlyMarketAndSupportsHTTP() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var receivedForeignCache = false
        let service = MarketService(root: root) { url, cache in
            if url.host == "192.168.1.2", cache != nil { receivedForeignCache = true }
            return Self.snapshot(url)
        }
        let id = try await service.saveSource("https://old.example.com")
        let newID = try await service.saveSource("http://192.168.1.2:3000")
        XCTAssertEqual(newID, id)
        XCTAssertEqual(service.sources.count, 1)
        XCTAssertEqual(service.source?.url, try MarketProtocol.catalogURL("http://192.168.1.2:3000"))
        XCTAssertEqual(service.catalogs.count, 1)
        XCTAssertFalse(receivedForeignCache)
        XCTAssertEqual(service.items().first?.item.packageURL.scheme, "http")
        let reloaded = MarketService(root: root)
        XCTAssertEqual(reloaded.sources, service.sources)
        XCTAssertEqual(reloaded.catalogs, service.catalogs)
    }

    @MainActor
    func testImportingFromAnotherMarketDoesNotReplaceTheConfiguredMarket() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var requests = 0
        let service = MarketService(root: root) { url, _ in requests += 1; return Self.snapshot(url) }
        await service.configureIfNeeded("http://first.example.com")
        let original = service.sources
        await service.configureIfNeeded("http://second.example.com")
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(service.sources, original)
        XCTAssertEqual(MarketService(root: root).sources, original)
    }

    @MainActor
    func testLatestMarketSelectionWinsWhenRequestsFinishOutOfOrder() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pending = PendingCatalog()
        let service = MarketService(root: root) { url, _ in
            if url.host == "slow.example.com" { return try await pending.load() }
            return Self.snapshot(url)
        }
        let earlier = Task { await service.configure("http://slow.example.com") }
        await pending.waitUntilLoading()
        await service.configure("http://latest.example.com")
        pending.finish(.success(Self.snapshot(try MarketProtocol.catalogURL("http://slow.example.com"))))
        await earlier.value
        XCTAssertEqual(service.sources.count, 1)
        XCTAssertEqual(service.source?.url.host, "latest.example.com")
        XCTAssertEqual(MarketService(root: root).source, service.source)
        XCTAssertNil(service.error)
    }

    @MainActor
    func testLegacyMultipleMarketsKeepTheFirstValidMarketAndBackupOtherSettings() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let invalid = MarketSource(url: URL(string: "file:///tmp/market.json")!)
        let first = MarketSource(url: try MarketProtocol.catalogURL("http://first.example.com"), name: "First")
        let second = MarketSource(url: try MarketProtocol.catalogURL("https://second.example.com"), name: "Second")
        let legacy = try JSONEncoder().encode([invalid, first, second])
        try legacy.write(to: root.appendingPathComponent("sources.json"))
        let snapshot = Self.snapshot(first.url)
        try JSONEncoder().encode(MarketSnapshot(pages: [snapshot.catalog])).write(to: root.appendingPathComponent("\(first.id.uuidString).json"))
        let service = MarketService(root: root)
        XCTAssertEqual(service.sources, [first])
        XCTAssertEqual(service.catalogs, [first.id: snapshot])
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("sources.legacy.json")), legacy)
        XCTAssertEqual(MarketService(root: root).sources, [first])
        XCTAssertNil(service.error)
    }

    @MainActor
    func testLegacyMigrationKeepsTheFirstMarketEvenWithoutACache() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = MarketSource(url: try MarketProtocol.catalogURL("http://first.example.com"))
        let second = MarketSource(url: try MarketProtocol.catalogURL("http://second.example.com"))
        try JSONEncoder().encode([first, second]).write(to: root.appendingPathComponent("sources.json"))
        let service = MarketService(root: root)
        XCTAssertEqual(service.source, first)
        XCTAssertEqual(service.sources.count, 1)
        XCTAssertTrue(service.catalogs.isEmpty)
    }

    @MainActor
    func testRefreshFromPreviousURLCannotOverwriteEditedSource() async throws {
        try await checkStaleRefresh(fails: false)
    }

    @MainActor
    func testRefreshErrorFromPreviousURLCannotMarkEditedSourceOffline() async throws {
        try await checkStaleRefresh(fails: true)
    }

    @MainActor
    private func checkStaleRefresh(fails: Bool) async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pending = PendingCatalog()
        var delayOldURL = false
        let service = MarketService(root: root) { url, _ in
            if delayOldURL && url.host == "old.example.com" { return try await pending.load() }
            return Self.snapshot(url)
        }
        let id = try await service.saveSource("https://old.example.com")
        delayOldURL = true
        let refresh = Task { await service.refresh(id) }
        await pending.waitUntilLoading()
        try await service.saveSource("https://new.example.com", replacing: id)
        let expected = service.sources
        let oldURL = try MarketProtocol.catalogURL("https://old.example.com")
        pending.finish(fails ? .failure(MarketCatalogError.offline) : .success(Self.snapshot(oldURL)))
        await refresh.value
        XCTAssertEqual(service.sources, expected)
        XCTAssertEqual(service.catalogs[id]?.catalog.name, "new.example.com")
        XCTAssertNil(service.error)
        XCTAssertFalse(service.isRefreshing)
    }

    @MainActor
    func testRemovalDuringVerificationDoesNotRestoreTheSource() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pending = PendingCatalog()
        let service = MarketService(root: root) { url, _ in
            if url.host == "new.example.com" { return try await pending.load() }
            return Self.snapshot(url)
        }
        let id = try await service.saveSource("https://old.example.com")
        let edit = Task { try await service.saveSource("https://new.example.com", replacing: id) }
        await pending.waitUntilLoading()
        service.removeSource(id)
        pending.finish(.success(Self.snapshot(try MarketProtocol.catalogURL("https://new.example.com"))))
        do { _ = try await edit.value; XCTFail("A removed source must not be restored") } catch { }
        XCTAssertTrue(service.sources.isEmpty)
        XCTAssertTrue(service.catalogs.isEmpty)
        XCTAssertTrue(MarketService(root: root).sources.isEmpty)
    }

    @MainActor
    func testUnwritableSettingsDoNotCommitAnEditInMemory() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MarketService(root: root) { url, _ in Self.snapshot(url) }
        let id = try await service.saveSource("https://original.example.com")
        let original = service.sources, catalogs = service.catalogs
        let settings = root.appendingPathComponent("sources.json")
        try FileManager.default.removeItem(at: settings)
        try FileManager.default.createDirectory(at: settings, withIntermediateDirectories: false)
        do {
            try await service.saveSource("https://new.example.com", replacing: id)
            XCTFail("A persistence failure must be surfaced")
        } catch { }
        XCTAssertEqual(service.sources, original)
        XCTAssertEqual(service.catalogs, catalogs)
    }
}

@MainActor
private final class PendingCatalog {
    private var response: CheckedContinuation<MarketCatalogPage, Error>?
    private var started: CheckedContinuation<Void, Never>?

    func load() async throws -> MarketCatalogPage {
        try await withCheckedThrowingContinuation { continuation in
            response = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilLoading() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ result: Result<MarketCatalogPage, Error>) {
        response?.resume(with: result)
        response = nil
    }
}
