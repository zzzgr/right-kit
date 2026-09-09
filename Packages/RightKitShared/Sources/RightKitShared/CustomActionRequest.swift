import AppKit
import Foundation

/// A URL wakes the app, but never supplies commands, action IDs or paths directly.
/// The unpredictable, single-use ticket must already exist in our shared container.
public struct CustomActionRequest: Codable, Equatable, Sendable {
    public let actionID: UUID
    public let targets: [URL]
    public let container: URL?
    public let createdAt: Date

    public var context: ActionContext { ActionContext(targets: targets, container: container) }

    public init(actionID: UUID, context: ActionContext, createdAt: Date = Date()) {
        self.actionID = actionID
        targets = context.targets
        container = context.container
        self.createdAt = createdAt
    }

    public static func enqueue(_ request: CustomActionRequest, in store: CustomActionStore) throws -> URL {
        guard !request.targets.isEmpty, request.targets.count <= 1000,
              request.targets.allSatisfy({ $0.isFileURL && !$0.path.contains("\0") }),
              request.container?.isFileURL != false else {
            throw CustomActionError.message(Strings.Custom.invalidSelection)
        }
        try store.prepare()
        // Remove only expired tickets; abandoned URLs must not accumulate indefinitely.
        let files = (try? FileManager.default.contentsOfDirectory(at: store.requestsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files.prefix(2000) {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               Date().timeIntervalSince(date) > 300 {
                try? FileManager.default.removeItem(at: file)
            }
        }
        let token = UUID()
        let destination = store.requestsDirectory.appendingPathComponent(token.uuidString + ".json")
        let data = try JSONEncoder().encode(request)
        guard data.count <= 1024 * 1024 else { throw CustomActionError.message(Strings.Custom.invalidSelection) }
        try data.write(to: destination, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        var url = URLComponents()
        url.scheme = ActionLink.scheme
        url.host = "custom"
        url.queryItems = [URLQueryItem(name: "ticket", value: token.uuidString)]
        guard let result = url.url else { throw CustomActionError.message(Strings.Custom.invalidRequest) }
        return result
    }

    public static func consume(_ url: URL, from store: CustomActionStore, now: Date = Date()) throws -> CustomActionRequest {
        guard url.scheme?.lowercased() == ActionLink.scheme, url.host?.lowercased() == "custom",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              query.count == 1, query[0].name == "ticket", let raw = query[0].value,
              let token = UUID(uuidString: raw) else { throw CustomActionError.message(Strings.Custom.invalidRequest) }
        let source = store.requestsDirectory.appendingPathComponent(token.uuidString + ".json")
        let claimed = store.requestsDirectory.appendingPathComponent(UUID().uuidString + ".claimed")
        // Atomic claim makes duplicate URL delivery harmless, even across processes.
        do { try FileManager.default.moveItem(at: source, to: claimed) }
        catch { throw CustomActionError.message(Strings.Custom.expiredRequest) }
        defer { try? FileManager.default.removeItem(at: claimed) }
        let attributes = try claimed.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
        guard attributes.isSymbolicLink != true, attributes.isRegularFile == true,
              (attributes.fileSize ?? 0) <= 1024 * 1024 else {
            throw CustomActionError.message(Strings.Custom.invalidRequest)
        }
        let request = try JSONDecoder().decode(Self.self, from: Data(contentsOf: claimed))
        guard (0...120).contains(now.timeIntervalSince(request.createdAt)),
              !request.targets.isEmpty, request.targets.count <= 1000,
              request.targets.allSatisfy({ $0.isFileURL && !$0.path.contains("\0") }), request.container?.isFileURL != false else {
            throw CustomActionError.message(Strings.Custom.expiredRequest)
        }
        return request
    }

    @discardableResult
    public static func handOff(_ request: CustomActionRequest, store: CustomActionStore) throws -> Bool {
        NSWorkspace.shared.open(try enqueue(request, in: store))
    }
}
