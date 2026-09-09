import AppKit
import Foundation
import RightKitShared

struct MarketSource: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var url: URL
    var name: String
    var refreshedAt: Date?
    var lastError: String?
    init(id: UUID = UUID(), url: URL, name: String = "") { self.id = id; self.url = url; self.name = name }
}

struct MarketEntry: Identifiable, Equatable {
    let item: MarketCatalog.Item
    let source: MarketSource
    var id: String { "\(source.id.uuidString):\(item.id)" }
}

struct MarketInstalledAction: Equatable {
    let id: String
    let version: String
    let marketURL: URL

    static func tracked(_ action: CustomAction) -> Self? {
        guard let metadata = action.packageMetadata, metadata.source == .market,
              metadata.tracksUpdates != false, let url = metadata.marketURL else { return nil }
        return Self(id: metadata.id, version: metadata.version, marketURL: url)
    }
}

struct PackageImportPreview: Identifiable {
    let id = UUID()
    let package: ActionPackage
    let source: CustomAction.PackageMetadata.Source
    var sourceURL: URL? = nil
    var marketURL: URL? = nil
    var sha256: String? = nil
    var versionsURL: URL? = nil
    var detailURL: URL? = nil
}

struct ActionImportRequest: Identifiable {
    enum State {
        case loading
        case ready(PackageImportPreview)
        case failed(String)
    }

    let id = UUID()
    var state: State
}

@MainActor
final class MarketService: ObservableObject {
    static let shared = MarketService()

    @Published private(set) var sources: [MarketSource] = []
    @Published private(set) var catalogs: [UUID: MarketCatalogPage] = [:]
    @Published private(set) var pagination = MarketPagination(total: 0)
    @Published private(set) var isRefreshing = false
    @Published private var entries: [MarketEntry] = []
    @Published var error: String?
    var source: MarketSource? { sources.first }
    let client = MarketHTTPClient()
    private let root: URL
    private let catalogLoader: (URL, MarketCatalogPage?) async throws -> MarketCatalogPage
    private var sourceFile: URL { root.appendingPathComponent("sources.json") }
    private var configurationRequestID = UUID()
    private var browsingRequestID = UUID()
    private var query = MarketQuery()
    private var installed: [MarketInstalledAction]?
    private var pageCache: [URL: MarketCatalogPage] = [:]
    private var cacheOrder: [URL] = []

    init(root: URL? = nil, catalogLoader: ((URL, MarketCatalogPage?) async throws -> MarketCatalogPage)? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RightKit/Markets", isDirectory: true)
        self.catalogLoader = catalogLoader ?? { url, cached in
            try await MarketHTTPClient().catalogPage(url, cached: cached)
        }
        loadSources()
    }

    func configure(_ raw: String) async {
        do {
            let url = try MarketProtocol.catalogURL(raw, allowHTTP: client.allowHTTP)
            if let source, source.url == url {
                configurationRequestID = UUID()
                await refresh(source.id)
                return
            }
            try await saveSource(raw)
        } catch is CancellationError {
            return
        } catch { self.error = error.localizedDescription }
    }

    func configureIfNeeded(_ raw: String) async {
        guard source == nil else { return }
        await configure(raw)
    }

    /// Verify an edited endpoint before committing it. Installed actions keep their
    /// original market identity; changing a subscription never rewrites provenance.
    @discardableResult
    func saveSource(_ raw: String, replacing id: UUID? = nil) async throws -> UUID {
        let url = try MarketProtocol.catalogURL(raw, allowHTTP: client.allowHTTP)
        let original = source
        if let id, original?.id != id { throw CustomActionError.message(Strings.Custom.marketSourceMissing) }
        let requestID = UUID()
        configurationRequestID = requestID
        let pageURL = try MarketQuery().url(for: url)
        let cached = pageCache[pageURL]
        let page: MarketCatalogPage
        do { page = try await catalogLoader(pageURL, cached) }
        catch {
            guard configurationRequestID == requestID else { throw CancellationError() }
            throw error
        }
        try Task.checkCancellation()
        guard configurationRequestID == requestID else { throw CancellationError() }
        guard page.url == pageURL else { throw MarketCatalogError.invalid }
        try page.validate(origin: url, allowHTTP: client.allowHTTP)
        // Refreshes, edits, and removal can finish while the request is in flight.
        if let original, !sources.contains(where: { $0.id == original.id && $0.url == original.url }) {
            throw CustomActionError.message(Strings.Custom.marketSourceMissing)
        }
        var source = MarketSource(id: original?.id ?? UUID(), url: url, name: page.catalog.name)
        source.refreshedAt = Date()
        try writeSources([source])
        browsingRequestID = UUID()
        isRefreshing = false
        query = MarketQuery(); installed = nil
        sources = [source]
        catalogs = [source.id: page]
        pageCache = [:]; cacheOrder = []
        remember(page)
        display(page.catalog.items, pagination: page.catalog.pagination ?? MarketPagination(total: page.catalog.items.count), source: source)
        try? JSONEncoder().encode(page).write(to: cacheURL(source.id), options: .atomic)
        error = nil
        return source.id
    }

    func removeSource(_ id: UUID) {
        guard source?.id == id else { return }
        do {
            try writeSources([])
            configurationRequestID = UUID()
            browsingRequestID = UUID()
            isRefreshing = false
            sources = []
            catalogs = [:]
            entries = []; pagination = MarketPagination(total: 0, pageSize: query.pageSize)
            pageCache = [:]; cacheOrder = []
            try? FileManager.default.removeItem(at: cacheURL(id))
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func refreshAll() async {
        await browse(query, installed: installed)
    }

    func refresh(_ id: UUID) async {
        guard source?.id == id else { return }
        await refreshAll()
    }

    /// The current market is queried before pagination. Update-only browsing asks
    /// for at most the 100 installed IDs, independent of the visible market page.
    func browse(_ query: MarketQuery, installed: [MarketInstalledAction]? = nil) async {
        let previousQuery = self.query, previousInstalled = self.installed
        self.query = query; self.installed = installed
        guard let source else { return }
        let requestID = UUID()
        browsingRequestID = requestID
        isRefreshing = true
        error = nil
        defer { if browsingRequestID == requestID { isRefreshing = false } }
        if previousQuery != query || previousInstalled != installed {
            entries = []
            pagination = MarketPagination(total: 0, pageSize: query.pageSize)
        }
        do {
            var requestQuery = query
            let tracked = installed?.filter {
                (try? MarketProtocol.catalogURL($0.marketURL.absoluteString)) == source.url
            }
            if let tracked {
                if tracked.isEmpty {
                    display([], pagination: MarketPagination(total: 0, pageSize: query.pageSize), source: source)
                    return
                }
                requestQuery.page = 1; requestQuery.pageSize = 100
                requestQuery.ids = Array(Set(tracked.map(\.id))).sorted()
            }
            let url = try requestQuery.url(for: source.url, allowHTTP: client.allowHTTP)
            if let cached = pageCache[url], cached.catalog.pagination != nil || cached.catalog.next == nil {
                show(cached, items: cached.catalog.items, query: query, tracked: tracked, source: source)
            }
            let page = try await loadPage(url, origin: source.url)
            // Legacy static catalogs do not understand queries. Keep their search
            // complete; markets with pagination metadata only load the requested page.
            let allItems = page.catalog.pagination == nil || tracked != nil
                ? try await collect(page, origin: source.url) : page.catalog.items
            try Task.checkCancellation()
            guard browsingRequestID == requestID,
                  let index = sources.firstIndex(where: { $0.id == source.id && $0.url == source.url }) else { return }
            catalogs[source.id] = page
            show(page, items: allItems, query: query, tracked: tracked, source: source)
            sources[index].name = page.catalog.name
            sources[index].refreshedAt = Date()
            sources[index].lastError = nil
            error = nil
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            // Keep the unfiltered first page for the next launch, not a previous search.
            if query == MarketQuery(), installed == nil {
                try JSONEncoder().encode(page).write(to: cacheURL(source.id), options: .atomic)
            }
            persistSources()
        } catch {
            guard !Task.isCancelled, browsingRequestID == requestID,
                  let index = sources.firstIndex(where: { $0.id == source.id && $0.url == source.url }) else { return }
            sources[index].lastError = error.localizedDescription
            persistSources()
            if entries.isEmpty { self.error = error.localizedDescription }
        }
    }

    func items() -> [MarketEntry] { entries }

    private func loadPage(_ url: URL, origin: URL) async throws -> MarketCatalogPage {
        let page = try await catalogLoader(url, pageCache[url])
        try Task.checkCancellation()
        guard page.url == url else { throw MarketCatalogError.invalid }
        try page.validate(origin: origin, allowHTTP: client.allowHTTP)
        remember(page)
        return page
    }

    private func remember(_ page: MarketCatalogPage) {
        pageCache[page.url] = page
        cacheOrder.removeAll { $0 == page.url }; cacheOrder.append(page.url)
        while cacheOrder.count > 12 { pageCache.removeValue(forKey: cacheOrder.removeFirst()) }
    }

    private func collect(_ first: MarketCatalogPage, origin: URL) async throws -> [MarketCatalog.Item] {
        var pages = [first.catalog], next = first.catalog.next
        var visited: Set<URL> = [first.url]
        while let url = next {
            try Task.checkCancellation()
            guard visited.count < 50, visited.insert(url).inserted else { throw MarketCatalogError.invalid }
            let page = try await loadPage(url, origin: origin)
            pages.append(page.catalog); next = page.catalog.next
        }
        let snapshot = MarketSnapshot(pages: pages)
        try snapshot.validate(origin: origin, allowHTTP: client.allowHTTP)
        return snapshot.items
    }

    private func show(_ page: MarketCatalogPage, items: [MarketCatalog.Item], query: MarketQuery,
                      tracked: [MarketInstalledAction]?, source: MarketSource) {
        if let pagination = page.catalog.pagination, tracked == nil {
            display(items, pagination: pagination, source: source)
        } else {
            let matches = items.filter { item in
                query.matches(item) && (tracked.map { metadata in
                    metadata.first(where: { $0.id == item.id }).map { MarketProtocol.isNewer(item.version, than: $0.version) } ?? false
                } ?? true)
            }.sorted {
                $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
            }
            let pagination = MarketPagination(total: matches.count, page: query.page, pageSize: query.pageSize)
            display(Array(matches.dropFirst((pagination.page - 1) * pagination.pageSize).prefix(pagination.pageSize)), pagination: pagination, source: source)
        }
    }

    private func display(_ items: [MarketCatalog.Item], pagination: MarketPagination, source: MarketSource) {
        self.pagination = pagination
        entries = items.prefix(pagination.pageSize).map { MarketEntry(item: $0, source: source) }
    }

    func preview(_ entry: MarketEntry) async throws -> PackageImportPreview {
        let (package, digest) = try await client.package(entry.item.packageURL, origin: entry.source.url, expected: entry.item)
        return PackageImportPreview(package: package, source: .market, sourceURL: entry.item.packageURL,
                                    marketURL: entry.source.url, sha256: digest,
                                    versionsURL: entry.item.versionsURL, detailURL: entry.item.detailURL)
    }

    func previewDirect(_ url: URL, marketURL: URL? = nil, sha256: String? = nil) async throws -> PackageImportPreview {
        let origin = try marketURL.map { try MarketProtocol.catalogURL($0.absoluteString, allowHTTP: client.allowHTTP) }
        let (package, digest) = try await client.package(url, origin: origin)
        if let sha256, digest != sha256 { throw MarketCatalogError.hashMismatch }
        // A link can claim a market, but only catalog/release metadata can bind
        // the downloaded bytes to that market's update identity.
        var preview = PackageImportPreview(package: package, source: .directURL, sourceURL: url, sha256: digest)
        guard let origin else { return preview }
        let lookup = try MarketQuery(ids: [package.id]).url(for: origin)
        let page = (try? await loadPage(lookup, origin: origin)) ?? pageCache[lookup]
        guard let page else { return preview }
        let items = page.catalog.pagination == nil ? (try? await collect(page, origin: origin)) ?? page.catalog.items : page.catalog.items
        guard let item = items.first(where: { $0.id == package.id }) else { return preview }
        var verified = false
        if item.version == package.version {
            guard item.sha256 == digest else { throw MarketCatalogError.hashMismatch }
            verified = true
        } else if let historyURL = item.versionsURL {
            var next: URL? = historyURL
            var visited = Set<URL>()
            while let pageURL = next, visited.count < 100, visited.insert(pageURL).inserted {
                try Task.checkCancellation()
                guard let history = try? await client.versions(pageURL, packageID: package.id, origin: origin) else { break }
                if let release = history.versions.first(where: { $0.version == package.version }) {
                    guard release.sha256 == digest else { throw MarketCatalogError.hashMismatch }
                    verified = true
                    break
                }
                next = history.next
            }
        }
        if verified {
            preview = PackageImportPreview(package: package, source: .market, sourceURL: url, marketURL: origin,
                                           sha256: digest, versionsURL: item.versionsURL, detailURL: item.detailURL)
        }
        return preview
    }

    private func cacheURL(_ id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).json") }

    private func loadSources() {
        guard let data = try? Data(contentsOf: sourceFile), let value = try? JSONDecoder().decode([MarketSource].self, from: data) else { return }
        for var source in value {
            guard let url = try? MarketProtocol.catalogURL(source.url.absoluteString, allowHTTP: client.allowHTTP) else { continue }
            source.url = url
            sources = [source]
            if let data = try? Data(contentsOf: cacheURL(source.id)) {
                if let page = try? JSONDecoder().decode(MarketCatalogPage.self, from: data),
                   page.url == (try? MarketQuery().url(for: url)),
                   (try? page.validate(origin: url, allowHTTP: client.allowHTTP)) != nil {
                    catalogs[source.id] = page
                    remember(page)
                    show(page, items: page.catalog.items, query: MarketQuery(), tracked: nil, source: source)
                } else if let snapshot = try? JSONDecoder().decode(MarketSnapshot.self, from: data),
                   (try? snapshot.validate(origin: url, allowHTTP: client.allowHTTP)) != nil {
                    let page = MarketCatalogPage(url: url, catalog: snapshot.pages[0])
                    catalogs[source.id] = page
                    remember(page)
                    show(page, items: page.catalog.pagination == nil ? snapshot.items : page.catalog.items,
                         query: MarketQuery(), tracked: nil, source: source)
                } else if let catalog = try? MarketCatalog.decode(data, origin: url, allowHTTP: client.allowHTTP), catalog.next == nil {
                    let page = MarketCatalogPage(url: url, catalog: catalog)
                    catalogs[source.id] = page
                    remember(page)
                    show(page, items: catalog.items, query: MarketQuery(), tracked: nil, source: source)
                }
            }
            break
        }
        if value.count > 1 {
            do {
                let backup = root.appendingPathComponent("sources.legacy.json")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try FileManager.default.copyItem(at: sourceFile, to: backup)
                }
                try writeSources(sources)
            } catch { self.error = error.localizedDescription }
        }
    }

    private func persistSources() {
        do {
            try writeSources(sources)
        } catch { self.error = error.localizedDescription }
    }

    private func writeSources(_ value: [MarketSource]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: sourceFile, options: .atomic)
    }
}
