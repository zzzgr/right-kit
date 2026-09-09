import Foundation

private final class MarketRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    let allowHTTP: Bool
    init(origin: URL, allowHTTP: Bool) { self.origin = origin; self.allowHTTP = allowHTTP }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, (try? MarketProtocol.validateURL(url, relativeTo: origin, allowHTTP: allowHTTP)) != nil else { completionHandler(nil); return }
        completionHandler(request)
    }
}

public struct MarketHTTPClient: Sendable {
    public let allowHTTP: Bool
    // HTTP and HTTPS markets share the same origin, size, and digest checks.
    public init(allowHTTP: Bool = true) { self.allowHTTP = allowHTTP }
    public func get(_ url: URL, origin: URL, limit: Int, etag: String? = nil, accept: String = "application/json") async throws -> (Data, HTTPURLResponse) {
        try MarketProtocol.validateURL(url, relativeTo: origin, allowHTTP: allowHTTP)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 15
        config.httpMaximumConnectionsPerHost = 3
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.setValue(accept, forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (bytes, response) = try await session.bytes(for: request, delegate: MarketRedirectGuard(origin: origin, allowHTTP: allowHTTP))
        guard let http = response as? HTTPURLResponse, let finalURL = http.url else { throw MarketCatalogError.invalid }
        try MarketProtocol.validateURL(finalURL, relativeTo: origin, allowHTTP: allowHTTP)
        guard http.statusCode == 200 || http.statusCode == 304, http.expectedContentLength <= limit else { throw MarketCatalogError.invalid }
        if http.statusCode == 304 { return (Data(), http) }
        var data = Data(); data.reserveCapacity(min(limit, 65536))
        for try await byte in bytes { guard data.count < limit else { throw ActionPackageError.tooLarge }; data.append(byte) }
        return (data, http)
    }
    public func package(_ url: URL, origin: URL? = nil, expected: MarketCatalog.Item? = nil) async throws -> (ActionPackage, String) {
        let (data, _) = try await get(url, origin: origin ?? url, limit: 8 * 1024 * 1024)
        let hash = MarketProtocol.hash(data)
        if let expected, hash != expected.sha256 { throw MarketCatalogError.hashMismatch }
        let package = try ActionPackage.decode(data)
        if let expected, package.id != expected.id || package.version != expected.version { throw MarketCatalogError.invalid }
        return (package, hash)
    }

    public func catalogPage(_ url: URL, cached: MarketCatalogPage? = nil) async throws -> MarketCatalogPage {
        let origin = try MarketProtocol.catalogURL(url.absoluteString, allowHTTP: allowHTTP)
        let cached = cached?.url == origin ? cached : nil
        if let cached { try cached.validate(origin: origin, allowHTTP: allowHTTP) }
        let (data, response) = try await get(origin, origin: origin, limit: 2 * 1024 * 1024, etag: cached?.etag)
        if response.statusCode == 304 {
            guard let cached else { throw MarketCatalogError.invalid }
            return cached
        }
        return MarketCatalogPage(url: origin, catalog: try MarketCatalog.decode(data, origin: origin, allowHTTP: allowHTTP),
                                 etag: response.value(forHTTPHeaderField: "ETag"))
    }

    public func catalog(_ url: URL, cached: MarketSnapshot? = nil) async throws -> MarketSnapshot {
        let origin = try MarketProtocol.catalogURL(url.absoluteString, allowHTTP: allowHTTP)
        if let cached { try cached.validate(origin: origin, allowHTTP: allowHTTP) }
        let (data, response) = try await get(origin, origin: origin, limit: 2 * 1024 * 1024, etag: cached?.etag)
        if response.statusCode == 304 {
            guard let cached else { throw MarketCatalogError.invalid }
            return cached
        }
        var pages = [try MarketCatalog.decode(data, origin: origin, allowHTTP: allowHTTP)]
        var visited: Set<URL> = [origin]
        while let next = pages.last?.next {
            try Task.checkCancellation()
            guard pages.count < 50, visited.insert(next).inserted else { throw MarketCatalogError.invalid }
            let (data, _) = try await get(next, origin: origin, limit: 2 * 1024 * 1024)
            pages.append(try MarketCatalog.decode(data, origin: origin, allowHTTP: allowHTTP))
        }
        let result = MarketSnapshot(pages: pages, etag: response.value(forHTTPHeaderField: "ETag"))
        try result.validate(origin: origin, allowHTTP: allowHTTP)
        return result
    }

    public func versions(_ url: URL, packageID: String, origin: URL) async throws -> MarketVersions {
        let (data, _) = try await get(url, origin: origin, limit: 1024 * 1024)
        return try MarketVersions.decode(data, packageID: packageID, origin: origin, allowHTTP: allowHTTP)
    }

    public func icon(_ item: MarketCatalog.Item, origin: URL) async throws -> Data? {
        guard let url = item.iconURL, let sha256 = item.iconSHA256 else { return nil }
        let (data, _) = try await get(url, origin: origin, limit: 262144, accept: "image/png")
        guard MarketProtocol.hash(data) == sha256 else { throw MarketCatalogError.hashMismatch }
        try ActionPackage.validatePNG(data)
        return data
    }
}
