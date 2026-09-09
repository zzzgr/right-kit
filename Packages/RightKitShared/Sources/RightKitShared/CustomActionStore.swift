import Foundation

public final class CustomActionStore {
    public let directory: URL
    public var catalogURL: URL { directory.appendingPathComponent("actions.json") }
    public var iconsDirectory: URL { directory.appendingPathComponent("Icons", isDirectory: true) }
    public var requestsDirectory: URL { directory.appendingPathComponent("Requests", isDirectory: true) }

    private struct Document<T: Codable>: Codable {
        var version = 1
        var actions: [T]
    }

    public init(directory: URL) { self.directory = directory }

    public static func sharedStore() throws -> CustomActionStore {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Preferences.appGroupID) else {
            throw CustomActionError.message(Strings.Custom.sharedContainerUnavailable)
        }
        return CustomActionStore(directory: container.appendingPathComponent("CustomActions", isDirectory: true))
    }

    public func prepare() throws {
        for url in [directory, iconsDirectory, requestsDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    public func load() throws -> [CustomAction] {
        let actions = try loadDocument(CustomAction.self)
        try validate(actions)
        return actions
    }
    public func loadMenu() throws -> [CustomMenuItem] { try loadDocument(CustomMenuItem.self) }

    private func loadDocument<T: Codable>(_ type: T.Type) throws -> [T] {
        guard FileManager.default.fileExists(atPath: catalogURL.path) else { return [] }
        let size = try catalogURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 32 * 1024 * 1024 else { throw CustomActionError.message(Strings.Custom.configurationTooLarge) }
        let document = try JSONDecoder().decode(Document<T>.self, from: Data(contentsOf: catalogURL))
        guard document.version == 1, document.actions.count <= 100 else {
            throw CustomActionError.message(Strings.Custom.unsupportedCatalog)
        }
        return document.actions
    }

    public func save(_ actions: [CustomAction]) throws {
        try validate(actions)
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(actions: actions))
        guard data.count <= 32 * 1024 * 1024 else { throw CustomActionError.message(Strings.Custom.configurationTooLarge) }
        try data.write(to: catalogURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: catalogURL.path)
    }

    private func validate(_ actions: [CustomAction]) throws {
        guard actions.count <= 100, Set(actions.map(\.id)).count == actions.count else {
            throw CustomActionError.message(Strings.Custom.invalidCatalog)
        }
        for action in actions {
            try action.validate()
            if case .image(let name) = action.icon, iconURL(named: name) == nil {
                throw CustomActionError.message(Strings.Custom.invalidIcon)
            }
        }
    }

    public func addIcon(png: Data) throws -> String {
        guard png.count <= 256 * 1024 else { throw CustomActionError.message(Strings.Custom.invalidIcon) }
        try prepare()
        let name = UUID().uuidString + ".png"
        try png.write(to: iconsDirectory.appendingPathComponent(name), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: iconsDirectory.appendingPathComponent(name).path)
        return name
    }

    public func iconURL(named name: String) -> URL? {
        guard name.hasSuffix(".png"), UUID(uuidString: String(name.dropLast(4))) != nil else { return nil }
        return iconsDirectory.appendingPathComponent(name)
    }
}

/// Cache the small, display-only projection until the atomic catalog file changes.
public final class CustomMenuCache {
    private struct Signature: Equatable {
        let modified: Date
        let size: UInt64
        let inode: UInt64
    }
    private var signature: Signature?
    private var items: [CustomMenuItem] = []

    public init() {}

    public func load(from store: CustomActionStore) throws -> [CustomMenuItem] {
        guard FileManager.default.fileExists(atPath: store.catalogURL.path) else {
            signature = nil
            items = []
            return []
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: store.catalogURL.path)
        let current = Signature(
            modified: attributes[.modificationDate] as? Date ?? .distantPast,
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        )
        if current != signature {
            let updated = try store.loadMenu()
            items = updated
            signature = current
        }
        return items
    }
}
