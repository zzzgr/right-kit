import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Portable, public representation of one RightKit action.
///
/// This protocol intentionally does not mirror ``CustomAction``. Local UUIDs,
/// interpreter paths, keychain references and Finder ordering never leave the Mac.
public struct ActionPackage: Codable, Equatable, Sendable {
    public static let format = "rightkit.action"
    public static let currentSchemaVersion = 1

    public struct Publisher: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var url: URL?
        public init(id: String, name: String, url: URL? = nil) { self.id = id; self.name = name; self.url = url }
    }

    public enum Icon: Codable, Equatable, Sendable {
        case symbol(String)
        case png(Data)

        private enum CodingKeys: String, CodingKey { case kind, name, data }
        private enum Kind: String, Codable { case symbol, png }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            switch try values.decode(Kind.self, forKey: .kind) {
            case .symbol: self = .symbol(try values.decode(String.self, forKey: .name))
            case .png: self = .png(try values.decode(Data.self, forKey: .data))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .symbol(let name):
                try values.encode(Kind.symbol, forKey: .kind)
                try values.encode(name, forKey: .name)
            case .png(let data):
                guard data.count <= 256 * 1024 else { throw ActionPackageError.invalid("icon.data") }
                try values.encode(Kind.png, forKey: .kind)
                try values.encode(data, forKey: .data)
            }
        }
    }

    public struct Rules: Codable, Equatable, Sendable {
        public var target: ActionInputRules.Target
        public var fileType: ActionInputRules.FileType
        public var extensions: [String]
        public var selection: ActionInputRules.Selection
        public init(target: ActionInputRules.Target = .both, fileType: ActionInputRules.FileType = .any, extensions: [String] = [], selection: ActionInputRules.Selection = .any) {
            self.target = target; self.fileType = fileType; self.extensions = extensions; self.selection = selection
        }
    }

    public struct Script: Codable, Equatable, Sendable {
        public var source: ScriptSource
        public var content: String
        public init(source: ScriptSource = .inline, content: String = "") { self.source = source; self.content = content }
    }

    public struct WorkingDirectory: Codable, Equatable, Sendable {
        public var mode: ScriptWorkingDirectory
        public var prompt: String?
        public init(mode: ScriptWorkingDirectory = .selection, prompt: String? = nil) { self.mode = mode; self.prompt = prompt }
    }

    public struct Environment: Codable, Equatable, Sendable {
        public var name: String
        public var isSecret: Bool
        public var value: String?
        public var hint: String?
        public init(name: String, isSecret: Bool, value: String? = nil, hint: String? = nil) { self.name = name; self.isSecret = isSecret; self.value = value; self.hint = hint }
    }

    public struct Action: Codable, Equatable, Sendable {
        public var title: String
        public var group: String
        public var icon: Icon
        public var rules: Rules
        public var language: ScriptLanguage
        public var script: Script
        public var batchMode: ScriptBatchMode
        public var workingDirectory: WorkingDirectory
        public var timeoutSeconds: Int
        public var environment: [Environment]
    }

    public struct Requirements: Codable, Equatable, Sendable {
        public struct PythonPackage: Codable, Equatable, Sendable { public var name: String; public var version: String? }
        public var python: String?
        public var pythonPackages: [PythonPackage]
        public var commands: [String]
        public init(python: String? = nil, pythonPackages: [PythonPackage] = [], commands: [String] = []) { self.python = python; self.pythonPackages = pythonPackages; self.commands = commands }
    }

    public var format: String
    public var schemaVersion: Int
    public var id: String
    public var version: String
    public var summary: String
    public var description: String
    public var publisher: Publisher
    public var license: String?
    public var homepage: URL?
    public var tags: [String]
    public var minRightKitVersion: String?
    public var minMacOSVersion: String?
    public var action: Action
    public var requirements: Requirements

    private enum CodingKeys: String, CodingKey { case format, schemaVersion, id, version, summary, description, publisher, license, homepage, tags, minRightKitVersion, minMacOSVersion, action, requirements }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format); schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(String.self, forKey: .id); version = try c.decode(String.self, forKey: .version)
        summary = try c.decode(String.self, forKey: .summary); description = try c.decode(String.self, forKey: .description)
        publisher = try c.decode(Publisher.self, forKey: .publisher); license = try c.decodeIfPresent(String.self, forKey: .license)
        homepage = try c.decodeIfPresent(URL.self, forKey: .homepage); tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        minRightKitVersion = try c.decodeIfPresent(String.self, forKey: .minRightKitVersion); minMacOSVersion = try c.decodeIfPresent(String.self, forKey: .minMacOSVersion)
        action = try c.decode(Action.self, forKey: .action); requirements = try c.decode(Requirements.self, forKey: .requirements)
    }

    public init(id: String, version: String, summary: String, description: String = "", publisher: Publisher, action: Action, requirements: Requirements = Requirements(), license: String? = nil, homepage: URL? = nil, tags: [String] = [], minRightKitVersion: String? = nil, minMacOSVersion: String? = nil) {
        self.format = Self.format; self.schemaVersion = Self.currentSchemaVersion; self.id = id; self.version = version; self.summary = summary; self.description = description; self.publisher = publisher; self.license = license; self.homepage = homepage; self.tags = tags; self.minRightKitVersion = minRightKitVersion; self.minMacOSVersion = minMacOSVersion; self.action = action; self.requirements = requirements
    }

    public func validate() throws {
        guard format == Self.format, schemaVersion == Self.currentSchemaVersion else { throw ActionPackageError.unsupportedVersion(schemaVersion) }
        guard MarketProtocol.isID(id), MarketProtocol.isID(publisher.id), !publisher.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, publisher.name.utf16.count <= 80 else { throw ActionPackageError.invalid("id / publisher") }
        guard MarketProtocol.isVersion(version) else { throw ActionPackageError.invalid("version") }
        if let minRightKitVersion, !MarketProtocol.isVersion(minRightKitVersion) { throw ActionPackageError.invalid("minRightKitVersion") }
        if let minMacOSVersion, !MarketProtocol.matches(minMacOSVersion, #"^\d+\.\d+(?:\.\d+)?$"#) { throw ActionPackageError.invalid("minMacOSVersion") }
        for url in [homepage, publisher.url].compactMap({ $0 }) { try MarketProtocol.validateURL(url) }
        guard [action.title, action.script.content, summary].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              [summary, description, action.title, action.group, action.script.content, publisher.name, license ?? "", action.workingDirectory.prompt ?? ""].allSatisfy({ !$0.contains("\0") }),
              tags.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.utf16.count <= 32 && !$0.contains("\0") }), (license?.utf16.count ?? 0) <= 80,
              (action.workingDirectory.prompt?.utf16.count ?? 0) <= 240 else { throw ActionPackageError.invalid("metadata") }
        guard action.rules.extensions.count <= 64, action.rules.extensions.allSatisfy({ MarketProtocol.matches($0, "^[a-z0-9][a-z0-9_-]{0,31}$") }) else { throw ActionPackageError.invalid("extensions") }
        guard requirements.pythonPackages.count <= 32, requirements.commands.count <= 32,
              requirements.commands.allSatisfy({ MarketProtocol.matches($0, "^[A-Za-z0-9][A-Za-z0-9._+-]{0,99}$") }),
              requirements.pythonPackages.allSatisfy({ MarketProtocol.matches($0.name, "^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$") }) else { throw ActionPackageError.invalid("requirements") }
        for constraint in [requirements.python].compactMap({ $0 }) + requirements.pythonPackages.compactMap(\.version) {
            guard constraint.count <= 80, MarketProtocol.matches(constraint, "^[0-9A-Za-z.*,<>=!~+ -]*$") else { throw ActionPackageError.invalid("requirements.version") }
        }
        guard summary.count <= 240, description.utf8.count <= 16 * 1024, action.title.count <= 80, action.group.count <= 60 else { throw ActionPackageError.invalid("metadata") }
        guard action.script.source == .inline, action.script.content.utf8.count <= 256 * 1024 else { throw ActionPackageError.invalid("action.script") }
        guard (1...3600).contains(action.timeoutSeconds), action.environment.count <= 64, tags.count <= 12 else { throw ActionPackageError.invalid("action") }
        if action.rules.fileType == .extensions && action.rules.extensions.isEmpty { throw ActionPackageError.invalid("action.rules.extensions") }
        var names = Set<String>()
        for variable in action.environment {
            guard variable.name.count <= 128, (variable.hint?.utf16.count ?? 0) <= 240, variable.hint?.contains("\0") != true,
                  MarketProtocol.matches(variable.name, "^[A-Za-z_][A-Za-z0-9_]*$"), !variable.name.hasPrefix("RIGHTKIT_"), names.insert(variable.name).inserted else { throw ActionPackageError.invalid("action.environment") }
            if variable.isSecret {
                guard variable.value == nil else { throw ActionPackageError.invalid("action.environment.value") }
            } else {
                guard let value = variable.value, !value.contains("\0"), value.utf8.count <= 16 * 1024 else { throw ActionPackageError.invalid("action.environment.value") }
            }
        }
        switch action.icon {
        case .symbol(let name): guard !name.trimmingCharacters(in: .whitespaces).isEmpty && name.utf16.count <= 80 && !name.contains("\0") else { throw ActionPackageError.invalid("action.icon") }
        case .png(let data): try Self.validatePNG(data)
        }
    }

    public static func validatePNG(_ data: Data) throws {
        guard data.count <= 262144, let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier, CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...64).contains(width), (1...64).contains(height), CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw ActionPackageError.invalid("action.icon") }
    }

    public func checkCompatibility(clientVersion: String = MarketProtocol.clientVersion, macOSVersion: String? = nil) throws {
        if let minimum = minRightKitVersion, MarketProtocol.isNewer(minimum, than: clientVersion) { throw MarketCatalogError.incompatible }
        if let minimum = minMacOSVersion {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let actual = macOSVersion ?? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            if minimum.compare(actual, options: .numeric) == .orderedDescending { throw MarketCatalogError.incompatible }
        }
    }

    public static func decode(_ data: Data) throws -> ActionPackage {
        guard data.count <= 8 * 1024 * 1024 else { throw ActionPackageError.tooLarge }
        let root = try MarketProtocol.object(JSONSerialization.jsonObject(with: data), keys: ["format", "schemaVersion", "id", "version", "summary", "description", "publisher", "license", "homepage", "tags", "minRightKitVersion", "minMacOSVersion", "action", "requirements"], path: "package")
        _ = try MarketProtocol.object(root["publisher"], keys: ["id", "name", "url"], path: "publisher")
        let a = try MarketProtocol.object(root["action"], keys: ["title", "group", "icon", "rules", "language", "script", "batchMode", "workingDirectory", "timeoutSeconds", "environment"], path: "action")
        let icon = a["icon"] as? [String: Any]
        _ = try MarketProtocol.object(icon, keys: icon?["kind"] as? String == "symbol" ? ["kind", "name"] : ["kind", "data"], path: "action.icon")
        _ = try MarketProtocol.object(a["rules"], keys: ["target", "fileType", "extensions", "selection"], path: "action.rules")
        _ = try MarketProtocol.object(a["script"], keys: ["source", "content"], path: "action.script")
        _ = try MarketProtocol.object(a["workingDirectory"], keys: ["mode", "prompt"], path: "action.workingDirectory")
        for value in a["environment"] as? [[String: Any]] ?? [] {
            _ = try MarketProtocol.object(value, keys: value["isSecret"] as? Bool == true ? ["name", "isSecret", "hint"] : ["name", "isSecret", "value", "hint"], path: "action.environment")
        }
        let r = try MarketProtocol.object(root["requirements"], keys: ["python", "pythonPackages", "commands"], path: "requirements")
        for value in r["pythonPackages"] as? [Any] ?? [] { _ = try MarketProtocol.object(value, keys: ["name", "version"], path: "requirements.pythonPackages") }
        let result = try JSONDecoder().decode(Self.self, from: data); try result.validate(); return result
    }

    /// Decode either plain JSON or one complete Markdown `json` code fence.
    public static func decodeClipboard(_ text: String) throws -> ActionPackage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if trimmed.hasPrefix("```"), trimmed.hasSuffix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            guard lines.count >= 3, lines[0].lowercased().trimmingCharacters(in: .whitespaces) == "```json", lines[lines.count - 1].trimmingCharacters(in: .whitespaces) == "```" else { throw ActionPackageError.invalid("clipboard") }
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        } else { json = trimmed }
        guard json.utf8.count <= 8 * 1024 * 1024 else { throw ActionPackageError.tooLarge }
        return try decode(Data(json.utf8))
    }

    public func encodedData() throws -> Data { try validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; let data = try encoder.encode(self); guard data.count <= 8 * 1024 * 1024 else { throw ActionPackageError.tooLarge }; return data }

    public func makeCustomAction(id: UUID = UUID(), icon: CustomActionIcon? = nil) throws -> CustomAction {
        try validate()
        if case .png = self.action.icon, icon == nil { throw ActionPackageError.invalid("action.icon") }
        var action = CustomAction(); action.id = id; action.title = self.action.title; action.group = self.action.group; action.icon = icon ?? { if case .symbol(let name) = self.action.icon { return .symbol(name) }; return .symbol("terminal") }(); action.rules.target = self.action.rules.target; action.rules.fileType = self.action.rules.fileType; action.rules.extensions = self.action.rules.extensions.joined(separator: ", "); action.rules.selection = self.action.rules.selection; action.language = self.action.language; action.source = .inline; action.script = self.action.script.content; action.batchMode = self.action.batchMode; action.workingDirectory = self.action.workingDirectory.mode; action.timeoutSeconds = self.action.timeoutSeconds; action.environment = self.action.environment.map { ScriptEnvironmentVariable(name: $0.name, value: $0.isSecret ? "" : ($0.value ?? ""), isSecret: $0.isSecret) }; return action
    }
}

public enum ActionPackageError: LocalizedError, Equatable, Sendable {
    case invalid(String)
    case unsupportedVersion(Int)
    case tooLarge
    public var errorDescription: String? { switch self { case .invalid(let field): return "动作包字段无效：\(field)"; case .unsupportedVersion(let version): return "不支持的动作包版本：\(version)"; case .tooLarge: return "动作包超过 8 MB 限制" } }
}

public enum ActionPackageExporter {
    public static func make(from action: CustomAction, iconData: Data? = nil, packageID: String, version: String = "1.0.0", publisher: ActionPackage.Publisher = .init(id: "local", name: "本机导出"), summary: String? = nil, description: String = "") throws -> ActionPackage {
        var action = action
        if action.source == .file {
            let url = URL(fileURLWithPath: action.scriptPath)
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 262144 else { throw ActionPackageError.tooLarge }
            action.script = try String(contentsOf: url, encoding: .utf8)
        }
        let icon: ActionPackage.Icon
        switch action.icon { case .symbol(let name): icon = .symbol(name); case .image: guard let iconData else { throw ActionPackageError.invalid("action.icon") }; icon = .png(iconData) }
        let env = action.environment.map { ActionPackage.Environment(name: $0.name, isSecret: $0.isSecret, value: $0.isSecret ? nil : $0.value, hint: action.packageMetadata?.environmentHints?[$0.name]) }
        let pkg = ActionPackage(id: packageID, version: version, summary: summary ?? action.title, description: description, publisher: publisher, action: .init(title: action.title, group: action.group, icon: icon, rules: .init(target: action.rules.target, fileType: action.rules.fileType, extensions: Array(action.rules.normalizedExtensions).sorted(), selection: action.rules.selection), language: action.language, script: .init(source: .inline, content: action.script), batchMode: action.batchMode, workingDirectory: .init(mode: action.workingDirectory), timeoutSeconds: action.timeoutSeconds, environment: env))
        var portable = pkg
        portable.requirements = action.packageMetadata?.requirements ?? .init()
        portable.description = action.packageMetadata?.description ?? description
        portable.tags = action.packageMetadata?.tags ?? []
        portable.action.workingDirectory.prompt = action.packageMetadata?.directoryPrompt
        try portable.validate(); return portable
    }
}
