import Foundation

public struct MarketPagination: Codable, Equatable, Sendable {
    public var page: Int
    public var pageSize: Int
    public var total: Int
    public var totalPages: Int

    public init(total: Int, page: Int = 1, pageSize: Int = 20) {
        self.total = max(0, total)
        self.pageSize = min(100, max(1, pageSize))
        self.totalPages = max(1, self.total / self.pageSize + (self.total % self.pageSize == 0 ? 0 : 1))
        self.page = min(max(1, page), totalPages)
    }

    public func validate(itemCount: Int) throws {
        guard total >= 0, (1...100).contains(pageSize), totalPages >= 1, (1...totalPages).contains(page),
              totalPages == max(1, total / pageSize + (total % pageSize == 0 ? 0 : 1)),
              itemCount == min(pageSize, total - (page - 1) * pageSize) else { throw MarketCatalogError.invalid }
    }
}

public struct MarketQuery: Equatable, Hashable, Sendable {
    public static let defaultPageSize = 20
    public static let pageSizes = [20, 50, 100]
    public var page: Int
    public var pageSize: Int
    public var search: String
    public var language: String
    public var ids: [String]?

    public init(page: Int = 1, pageSize: Int = 20, search: String = "", language: String = "all", ids: [String]? = nil) {
        self.page = page; self.pageSize = pageSize; self.search = search; self.language = language; self.ids = ids
    }

    public func url(for market: URL, allowHTTP: Bool = true) throws -> URL {
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...1_000_000).contains(page), (1...100).contains(pageSize), search.utf16.count <= 200,
              !search.contains("\0"), ["all", "python", "zsh", "bash", "sh"].contains(language),
              ids.map({ $0.count <= 100 && $0.allSatisfy(MarketProtocol.isID) }) ?? true else { throw MarketCatalogError.invalid }
        let origin = try MarketProtocol.catalogURL(market.absoluteString, allowHTTP: allowHTTP)
        guard var parts = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { throw MarketCatalogError.invalidURL }
        let names = Set(["page", "pageSize", "cursor", "q", "language", "tag", "sort", "status", "ids"])
        var params = (parts.queryItems ?? []).filter { !names.contains($0.name) }
        if page > 1 { params.append(URLQueryItem(name: "page", value: String(page))) }
        if pageSize != Self.defaultPageSize { params.append(URLQueryItem(name: "pageSize", value: String(pageSize))) }
        if !search.isEmpty { params.append(URLQueryItem(name: "q", value: search)) }
        if language != "all" { params.append(URLQueryItem(name: "language", value: language)) }
        if let ids { params.append(URLQueryItem(name: "ids", value: Array(Set(ids)).sorted().joined(separator: ","))) }
        parts.queryItems = params.isEmpty ? nil : params
        guard let url = parts.url else { throw MarketCatalogError.invalidURL }
        return url
    }

    public func matches(_ item: MarketCatalog.Item) -> Bool {
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (search.isEmpty || "\(item.title) \(item.summary) \(item.tags.joined(separator: " "))".localizedCaseInsensitiveContains(search))
            && (language == "all" || item.language.rawValue == language) && (ids.map { $0.contains(item.id) } ?? true)
    }
}

/// One response, bound to its exact query URL. It never represents a complete catalog.
public struct MarketCatalogPage: Codable, Equatable, Sendable {
    public var url: URL
    public var catalog: MarketCatalog
    public var etag: String?

    public init(url: URL, catalog: MarketCatalog, etag: String? = nil) {
        self.url = url; self.catalog = catalog; self.etag = etag
    }

    public func validate(origin: URL, allowHTTP: Bool = true) throws {
        try MarketProtocol.validateURL(url, relativeTo: origin, allowHTTP: allowHTTP)
        try catalog.validate(origin: origin, allowHTTP: allowHTTP)
    }
}
