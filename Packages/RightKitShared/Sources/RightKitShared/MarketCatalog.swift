import Foundation

public struct MarketCatalog: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var version: String
        public var title: String
        public var summary: String
        public var language: ScriptLanguage
        public var target: ActionInputRules.Target
        public var tags: [String]
        public var group: String?
        public var symbol: String
        public var packageURL: URL
        public var sha256: String
        public var updatedAt: Date
        public var iconURL: URL?
        public var detailURL: URL?
        public var versionsURL: URL?
        public var iconSHA256: String?
        public init(id: String, version: String, title: String, summary: String, language: ScriptLanguage, target: ActionInputRules.Target, tags: [String], symbol: String, packageURL: URL, sha256: String, updatedAt: Date, iconURL: URL? = nil, iconSHA256: String? = nil, detailURL: URL? = nil, versionsURL: URL? = nil, group: String? = nil) { self.id = id; self.version = version; self.title = title; self.summary = summary; self.language = language; self.target = target; self.tags = tags; self.symbol = symbol; self.packageURL = packageURL; self.sha256 = sha256; self.updatedAt = updatedAt; self.iconURL = iconURL; self.iconSHA256 = iconSHA256; self.detailURL = detailURL; self.versionsURL = versionsURL; self.group = group }
    }
    public var format: String
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var homepage: URL
    public var generatedAt: Date
    public var items: [Item]
    public var next: URL?
    public var pagination: MarketPagination?
    public var tags: [String]?
    public var groups: [String]?
    public init(format: String = "rightkit.market", schemaVersion: Int = 1, id: String, name: String, homepage: URL, generatedAt: Date, items: [Item], next: URL? = nil, pagination: MarketPagination? = nil, tags: [String]? = nil, groups: [String]? = nil) { self.format = format; self.schemaVersion = schemaVersion; self.id = id; self.name = name; self.homepage = homepage; self.generatedAt = generatedAt; self.items = items; self.next = next; self.pagination = pagination; self.tags = tags; self.groups = groups }
    public func validate(origin: URL? = nil, allowHTTP: Bool = true) throws {
        guard format == "rightkit.market", schemaVersion == 1, MarketProtocol.isID(id), !name.isEmpty, name.count <= 80, items.count <= 200,
              Set(items.map(\.id)).count == items.count else { throw MarketCatalogError.invalid }
        try MarketProtocol.validateURL(homepage, allowHTTP: allowHTTP)
        if let pagination {
            try pagination.validate(itemCount: items.count)
            guard (next != nil) == (pagination.page < pagination.totalPages) else { throw MarketCatalogError.invalid }
        }
        if let tags, !tags.allSatisfy({ $0.utf16.count <= 32 }) { throw MarketCatalogError.invalid }
        if let groups, !groups.allSatisfy({ $0.utf16.count <= 60 && !$0.contains("\0") }) { throw MarketCatalogError.invalid }
        if let next { try MarketProtocol.validateURL(next, relativeTo: origin, allowHTTP: allowHTTP) }
        for item in items {
            guard MarketProtocol.isID(item.id), MarketProtocol.isVersion(item.version), !item.title.isEmpty, item.title.utf16.count <= 80,
                  item.summary.utf16.count <= 240, item.tags.count <= 12, item.tags.allSatisfy({ $0.utf16.count <= 32 }),
                  item.group.map({ $0.utf16.count <= 60 && !$0.contains("\0") }) ?? true,
                  !item.symbol.isEmpty, item.symbol.count <= 80, MarketProtocol.matches(item.sha256, "^[a-f0-9]{64}$") else { throw MarketCatalogError.invalid }
            try MarketProtocol.validateURL(item.packageURL, relativeTo: origin, allowHTTP: allowHTTP)
            for url in [item.detailURL, item.versionsURL].compactMap({ $0 }) {
                try MarketProtocol.validateURL(url, relativeTo: origin, allowHTTP: allowHTTP)
            }
            if let iconURL = item.iconURL {
                try MarketProtocol.validateURL(iconURL, relativeTo: origin, allowHTTP: allowHTTP)
                guard let digest = item.iconSHA256, MarketProtocol.matches(digest, "^[a-f0-9]{64}$") else { throw MarketCatalogError.invalid }
            }
        }
    }
    public static func decode(_ data: Data, origin: URL, allowHTTP: Bool = true) throws -> MarketCatalog {
        guard data.count <= 2 * 1024 * 1024 else { throw MarketCatalogError.invalid }
        let catalog = try MarketProtocol.decoder.decode(Self.self, from: data)
        try catalog.validate(origin: origin, allowHTTP: allowHTTP); return catalog
    }
}

public enum MarketCatalogError: LocalizedError, Equatable, Sendable {
    case invalid, invalidURL, invalidLink, httpsRequired, offline, hashMismatch, incompatible

    public var errorDescription: String? {
        switch self {
        case .invalid: return Strings.Custom.invalidMarketCatalog
        case .invalidURL: return Strings.Custom.invalidMarketURL
        case .invalidLink: return Strings.Custom.invalidMarketLink
        case .httpsRequired: return Strings.Custom.marketHTTPSRequired
        case .offline: return Strings.Custom.marketUnavailable
        case .hashMismatch: return Strings.Custom.marketHashMismatch
        case .incompatible: return Strings.Custom.marketIncompatible
        }
    }
}
