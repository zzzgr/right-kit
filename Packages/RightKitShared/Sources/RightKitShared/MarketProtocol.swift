import CryptoKit
import Foundation

public enum MarketProtocol {
    public static let clientVersion = "1.2.1"
    public static let semverPattern = #"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"#
    public static func matches(_ value: String, _ pattern: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern), let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return false }
        return match.range.length == value.utf16.count
    }
    public static func isVersion(_ value: String) -> Bool { value.count <= 120 && matches(value, semverPattern) }
    public static func isID(_ value: String) -> Bool { matches(value, "^[A-Za-z0-9._-]{1,120}$") && value != "." && value != ".." }
    public static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard isVersion(candidate), isVersion(current) else { return false }
        let a = candidate.split(separator: "+")[0].split(separator: "-", maxSplits: 1).map(String.init)
        let b = current.split(separator: "+")[0].split(separator: "-", maxSplits: 1).map(String.init)
        if a[0] != b[0] { return a[0].compare(b[0], options: .numeric) == .orderedDescending }
        if a.count != b.count { return a.count == 1 }
        guard a.count == 2 else { return false }
        let left = a[1].split(separator: ".").map(String.init), right = b[1].split(separator: ".").map(String.init)
        for (l, r) in zip(left, right) where l != r {
            let ln = matches(l, "^[0-9]+$"), rn = matches(r, "^[0-9]+$")
            if ln != rn { return !ln }
            return l.compare(r, options: ln ? .numeric : .literal) == .orderedDescending
        }
        return left.count > right.count
    }

    public static func validateURL(_ url: URL, relativeTo origin: URL? = nil, allowHTTP: Bool = true) throws {
        guard url.host?.isEmpty == false, url.user == nil, url.password == nil, url.fragment == nil else { throw MarketCatalogError.invalidURL }
        let scheme = url.scheme?.lowercased()
        guard scheme == "https" || (allowHTTP && scheme == "http") else {
            throw scheme == "http" ? MarketCatalogError.httpsRequired : MarketCatalogError.invalidURL
        }
        if let origin {
            guard url.scheme?.lowercased() == origin.scheme?.lowercased(), url.host?.lowercased() == origin.host?.lowercased(),
                  (url.port ?? (scheme == "https" ? 443 : 80)) == (origin.port ?? (origin.scheme?.lowercased() == "https" ? 443 : 80)) else { throw MarketCatalogError.invalid }
        }
    }
    public static func catalogURL(_ raw: String, allowHTTP: Bool = true) throws -> URL {
        guard var parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), let url = parts.url else { throw MarketCatalogError.invalidURL }
        try validateURL(url, allowHTTP: allowHTTP)
        parts.scheme = parts.scheme?.lowercased(); parts.host = parts.host?.lowercased()
        if parts.port == (parts.scheme == "https" ? 443 : 80) { parts.port = nil }
        if !url.path.lowercased().hasSuffix(".json") { parts.path = "/.well-known/rightkit-market.json"; parts.query = nil }
        guard let result = parts.url else { throw MarketCatalogError.invalidURL }
        return result
    }
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: raw) else { throw MarketCatalogError.invalid }
            return date
        }
        return decoder
    }
    static func object(_ value: Any?, keys: Set<String>, path: String) throws -> [String: Any] {
        guard let object = value as? [String: Any], Set(object.keys).isSubset(of: keys) else { throw ActionPackageError.invalid(path) }
        return object
    }
}

public struct MarketLink: Equatable, Sendable {
    public enum Kind: String, Sendable { case importAction = "import", market }
    public let kind: Kind
    public let url: URL
    public let marketURL: URL?
    public let sha256: String?

    public static func parse(_ url: URL, allowHTTP: Bool = true) throws -> MarketLink {
        guard url.scheme?.lowercased() == "rightkit", let kind = Kind(rawValue: url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil, url.path.isEmpty || url.path == "/",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              Set(items.map(\.name)).count == items.count,
              items.allSatisfy({ (kind == .market ? ["url"] : ["url", "market", "sha256"]).contains($0.name) && $0.value?.isEmpty == false }),
              let value = items.first(where: { $0.name == "url" })?.value, let target = URL(string: value) else { throw MarketCatalogError.invalidLink }
        try MarketProtocol.validateURL(target, allowHTTP: allowHTTP)
        let marketURL = try items.first(where: { $0.name == "market" })?.value.map {
            try MarketProtocol.catalogURL($0, allowHTTP: allowHTTP)
        }
        if let marketURL { try MarketProtocol.validateURL(marketURL, relativeTo: target, allowHTTP: allowHTTP) }
        let sha256 = items.first(where: { $0.name == "sha256" })?.value
        if let sha256, !MarketProtocol.matches(sha256, "^[a-f0-9]{64}$") { throw MarketCatalogError.invalidLink }
        return MarketLink(kind: kind, url: target, marketURL: marketURL, sha256: sha256)
    }
}
