import Foundation

public struct MarketSnapshot: Codable, Equatable, Sendable {
    public var pages: [MarketCatalog]
    public var etag: String?
    public var items: [MarketCatalog.Item] { pages.flatMap(\.items) }
    public init(pages: [MarketCatalog], etag: String? = nil) { self.pages = pages; self.etag = etag }

    public func validate(origin: URL, allowHTTP: Bool = true) throws {
        guard let first = pages.first, pages.count <= 50, pages.last?.next == nil else { throw MarketCatalogError.invalid }
        if let pagination = first.pagination {
            guard pagination.page == 1, pages.count == pagination.totalPages else { throw MarketCatalogError.invalid }
        }
        var ids = Set<String>()
        for (index, page) in pages.enumerated() {
            try page.validate(origin: origin, allowHTTP: allowHTTP)
            guard page.id == first.id, page.homepage == first.homepage, page.generatedAt == first.generatedAt,
                  index == pages.count - 1 || page.next != nil else { throw MarketCatalogError.invalid }
            if let pagination = first.pagination {
                guard page.pagination?.page == index + 1, page.pagination?.pageSize == pagination.pageSize,
                      page.pagination?.total == pagination.total, page.pagination?.totalPages == pagination.totalPages else { throw MarketCatalogError.invalid }
            } else if page.pagination != nil { throw MarketCatalogError.invalid }
            for item in page.items where !ids.insert(item.id).inserted { throw MarketCatalogError.invalid }
        }
    }
}

public struct MarketVersions: Decodable, Sendable {
    public struct Release: Decodable, Identifiable, Sendable {
        public let version: String
        public let notes: String
        public let sha256: String
        public let createdAt: Date
        public let packageURL: URL
        public var id: String { version }
    }
    public let format: String
    public let schemaVersion: Int
    public let id: String
    public let versions: [Release]
    public let next: URL?

    public static func decode(_ data: Data, packageID: String, origin: URL, allowHTTP: Bool = true) throws -> Self {
        guard data.count <= 1024 * 1024 else { throw MarketCatalogError.invalid }
        let result = try MarketProtocol.decoder.decode(Self.self, from: data)
        guard result.format == "rightkit.versions", result.schemaVersion == 1, result.id == packageID,
              result.versions.count <= 50, Set(result.versions.map(\.version)).count == result.versions.count else { throw MarketCatalogError.invalid }
        for release in result.versions {
            guard MarketProtocol.isVersion(release.version), release.notes.utf8.count <= 16384,
                  MarketProtocol.matches(release.sha256, "^[a-f0-9]{64}$") else { throw MarketCatalogError.invalid }
            try MarketProtocol.validateURL(release.packageURL, relativeTo: origin, allowHTTP: allowHTTP)
        }
        if let next = result.next { try MarketProtocol.validateURL(next, relativeTo: origin, allowHTTP: allowHTTP) }
        return result
    }
}
