import Foundation
import UniformTypeIdentifiers

public enum ScriptLanguage: String, Codable, CaseIterable, Sendable {
    case python, zsh, bash, sh

    public var title: String {
        switch self {
        case .python: return "Python"
        case .zsh: return "Shell · zsh"
        case .bash: return "Shell · bash"
        case .sh: return "Shell · sh"
        }
    }

    public var fileExtension: String { self == .python ? "py" : "sh" }
}

public enum ScriptSource: String, Codable, CaseIterable, Sendable {
    case inline, file
}

public enum ScriptBatchMode: String, Codable, CaseIterable, Sendable {
    case together, individually
}

public enum ScriptWorkingDirectory: String, Codable, CaseIterable, Sendable {
    case selection, finder, custom
}

public enum CustomActionIcon: Codable, Equatable, Sendable {
    case symbol(String)
    /// A UUID-named PNG copied into the shared container, never an external path.
    case image(String)
}

public struct ActionInputRules: Codable, Equatable, Sendable {
    public enum Target: String, Codable, CaseIterable, Sendable { case both, files, folders }
    public enum FileType: String, Codable, CaseIterable, Sendable { case any, images, extensions }
    public enum Selection: String, Codable, CaseIterable, Sendable { case any, single, multiple }

    public var target: Target = .both
    public var fileType: FileType = .any
    public var extensions: String = ""
    public var selection: Selection = .any

    public init() {}

    public var normalizedExtensions: Set<String> {
        Set(extensions.lowercased().components(separatedBy: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;，；")))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "*.")) }
            .filter { !$0.isEmpty })
    }

    /// Every selected item must match. A mixed selection is never silently reduced.
    public func matches(_ context: ActionContext) -> Bool {
        guard !context.targets.isEmpty else { return false }
        if selection == .single && context.targets.count != 1 { return false }
        if selection == .multiple && context.targets.count < 2 { return false }
        return context.targets.allSatisfy { url in
            guard url.isFileURL else { return false }
            if PathUtilities.isDirectory(url) { return target != .files }
            guard target != .folders else { return false }
            switch fileType {
            case .any: return true
            case .images: return UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .image) == true
            case .extensions: return normalizedExtensions.contains(url.pathExtension.lowercased())
            }
        }
    }
}

public struct ScriptEnvironmentVariable: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var value: String
    public var isSecret: Bool

    public init(id: UUID = UUID(), name: String = "", value: String = "", isSecret: Bool = false) {
        self.id = id
        self.name = name
        self.value = value
        self.isSecret = isSecret
    }

    private enum CodingKeys: String, CodingKey { case id, name, value, isSecret }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        isSecret = try values.decode(Bool.self, forKey: .isSecret)
        value = isSecret ? "" : try values.decode(String.self, forKey: .value)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(isSecret, forKey: .isSecret)
        // Secret values live in Keychain. Neither the shared catalog nor exports get them.
        try values.encode(isSecret ? "" : value, forKey: .value)
    }
}

public struct CustomAction: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var title = ""
    public var group = ""
    public var isEnabled = true
    public var icon: CustomActionIcon = .symbol("terminal")
    public var rules = ActionInputRules()
    public var language: ScriptLanguage = .zsh
    public var source: ScriptSource = .inline
    public var script = ""
    public var scriptPath = ""
    /// Empty means auto-detect Python, or use the selected system shell.
    public var interpreterPath = ""
    public var batchMode: ScriptBatchMode = .together
    public var workingDirectory: ScriptWorkingDirectory = .selection
    public var customWorkingDirectory = ""
    public var timeoutSeconds = 120
    public var environment: [ScriptEnvironmentVariable] = []
    /// Optional provenance for actions imported from the web or clipboard.
    public var packageMetadata: PackageMetadata? = nil

    public struct PackageMetadata: Codable, Equatable, Sendable {
        public enum Source: String, Codable, Sendable { case clipboard, market, directURL }
        public var id: String
        public var version: String
        public var source: Source
        public var sourceURL: URL?
        public var marketURL: URL?
        public var sha256: String?
        public var importedAt: Date
        public var summary: String?
        public var requirements: ActionPackage.Requirements?
        public var description: String? = nil
        public var tags: [String]? = nil
        public var directoryPrompt: String? = nil
        public var environmentHints: [String: String]? = nil
        public var baseline: ActionPackage? = nil
        public var tracksUpdates: Bool? = nil
        public init(id: String, version: String, source: Source, sourceURL: URL? = nil, marketURL: URL? = nil, sha256: String? = nil, importedAt: Date = Date(), summary: String? = nil, requirements: ActionPackage.Requirements? = nil) { self.id = id; self.version = version; self.source = source; self.sourceURL = sourceURL; self.marketURL = marketURL; self.sha256 = sha256; self.importedAt = importedAt; self.summary = summary; self.requirements = requirements }
    }

    public init() {}

    public var menuItem: CustomMenuItem {
        CustomMenuItem(id: id, title: title, group: group, isEnabled: isEnabled, icon: icon, rules: rules)
    }

    public func validate(forExecution: Bool = false) throws {
        typealias C = Strings.Custom
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80, group.count <= 60 else {
            throw CustomActionError.message(C.invalidTitle)
        }
        guard (1...3600).contains(timeoutSeconds) else { throw CustomActionError.message(C.invalidTimeout) }
        guard rules.target == .folders || rules.fileType != .extensions || !rules.normalizedExtensions.isEmpty else {
            throw CustomActionError.message(C.invalidExtensions)
        }
        guard interpreterPath.isEmpty || interpreterPath.hasPrefix("/") else {
            throw CustomActionError.message(C.absoluteInterpreter)
        }
        if workingDirectory == .custom && !customWorkingDirectory.hasPrefix("/") {
            throw CustomActionError.message(C.invalidDirectory)
        }
        var names = Set<String>()
        var ids = Set<UUID>()
        for variable in environment {
            guard variable.name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil,
                  !variable.name.hasPrefix("RIGHTKIT_"), names.insert(variable.name).inserted,
                  ids.insert(variable.id).inserted else {
                throw CustomActionError.message(C.invalidEnvironment)
            }
            guard !variable.value.contains("\0"), variable.value.utf8.count <= 16 * 1024 else {
                throw CustomActionError.message(C.invalidEnvironmentValue)
            }
        }
        guard script.utf8.count <= 256 * 1024, environment.count <= 64 else {
            throw CustomActionError.message(C.configurationTooLarge)
        }
        if isEnabled || forExecution {
            if source == .inline && script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CustomActionError.message(C.emptyScript)
            }
            if source == .file && !scriptPath.hasPrefix("/") {
                throw CustomActionError.message(C.invalidScriptPath)
            }
        }
        for text in [script, scriptPath, interpreterPath, customWorkingDirectory] {
            guard !text.contains("\0") else { throw CustomActionError.message(C.invalidConfiguration) }
        }
    }
}

/// Finder decodes only these fields; script bodies and environment values are ignored.
public struct CustomMenuItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let group: String
    public let isEnabled: Bool
    public let icon: CustomActionIcon
    public let rules: ActionInputRules

    public func isAvailable(in context: ActionContext) -> Bool { isEnabled && rules.matches(context) }
}

public enum CustomActionError: LocalizedError, Equatable {
    case message(String)

    public var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}
