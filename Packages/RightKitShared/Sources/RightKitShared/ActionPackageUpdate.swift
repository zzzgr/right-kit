import Foundation

public enum ActionPackageUpdate {
    public static func matches(_ metadata: CustomAction.PackageMetadata?, packageID: String, source: CustomAction.PackageMetadata.Source, marketURL: URL?, sourceURL: URL?) -> Bool {
        guard let metadata, metadata.tracksUpdates != false, metadata.id == packageID, metadata.source == source else { return false }
        switch source {
        case .market:
            guard let left = metadata.marketURL, let right = marketURL else { return false }
            guard let canonicalLeft = try? MarketProtocol.catalogURL(left.absoluteString, allowHTTP: true),
                  let canonicalRight = try? MarketProtocol.catalogURL(right.absoluteString, allowHTTP: true) else { return false }
            return canonicalLeft == canonicalRight
        case .directURL: return metadata.sourceURL == sourceURL
        case .clipboard: return true
        }
    }

    /// Three-way merge: preserve a local edit when the publisher left that field alone.
    /// Conflicting fields use the explicitly selected local or incoming preference.
    public static func merge(_ incoming: CustomAction, with local: CustomAction, package: ActionPackage, preferLocal: Bool, localIconData: Data? = nil) -> CustomAction {
        var result = incoming
        let baseline = local.packageMetadata?.baseline
        func choose<T: Equatable>(_ old: T?, _ local: T, _ remote: T) -> T {
            guard let old else { return preferLocal ? local : remote }
            if remote == old { return local }
            if local != old && preferLocal { return local }
            return remote
        }
        result.id = local.id; result.isEnabled = local.isEnabled
        result.interpreterPath = local.interpreterPath; result.customWorkingDirectory = local.customWorkingDirectory
        result.title = choose(baseline?.action.title, local.title, incoming.title)
        result.group = choose(baseline?.action.group, local.group, incoming.group)
        result.language = choose(baseline?.action.language, local.language, incoming.language)
        result.script = choose(baseline?.action.script.content, local.script, incoming.script)
        result.batchMode = choose(baseline?.action.batchMode, local.batchMode, incoming.batchMode)
        result.timeoutSeconds = choose(baseline?.action.timeoutSeconds, local.timeoutSeconds, incoming.timeoutSeconds)
        result.workingDirectory = choose(baseline?.action.workingDirectory.mode, local.workingDirectory, incoming.workingDirectory)
        let oldRules = baseline?.action.rules
        result.rules.target = choose(oldRules?.target, local.rules.target, incoming.rules.target)
        result.rules.fileType = choose(oldRules?.fileType, local.rules.fileType, incoming.rules.fileType)
        result.rules.selection = choose(oldRules?.selection, local.rules.selection, incoming.rules.selection)
        result.rules.extensions = choose(oldRules.map { $0.extensions.joined(separator: ", ") }, local.rules.extensions, incoming.rules.extensions)
        let localIcon: ActionPackage.Icon?
        switch local.icon {
        case .symbol(let name): localIcon = .symbol(name)
        case .image: localIcon = localIconData.map { .png($0) }
        }
        if let baseline {
            if baseline.action.icon == package.action.icon || (preferLocal && localIcon != baseline.action.icon) {
                result.icon = local.icon
            }
        } else if preferLocal { result.icon = local.icon }
        if preferLocal && local.source == .file { result.source = .file; result.scriptPath = local.scriptPath }

        // Merge presence as well as values: local additions/deletions must survive
        // an unrelated release, and removed publisher defaults should stay removed.
        let incomingNames = Set(incoming.environment.map(\.name))
        let names = incoming.environment.map(\.name) + local.environment.map(\.name).filter { !incomingNames.contains($0) }
        result.environment = names.compactMap { name in
            let candidate = incoming.environment.first { $0.name == name }
            let existing = local.environment.first { $0.name == name }
            let original = baseline?.action.environment.first { $0.name == name }
            let oldValue = original.map { EnvironmentValue(isSecret: $0.isSecret, value: $0.value) }
            let localValue = existing.map { EnvironmentValue(isSecret: $0.isSecret, value: $0.value) }
            let remoteValue = candidate.map { EnvironmentValue(isSecret: $0.isSecret, value: $0.value) }
            let keepLocal = remoteValue == oldValue || (localValue != oldValue && preferLocal)
            guard var selected = keepLocal ? existing : candidate else { return nil }
            if let existing, existing.isSecret == selected.isSecret {
                selected.id = existing.id
                if selected.isSecret { selected.value = existing.value }
            }
            return selected
        }
        return result
    }

    private struct EnvironmentValue: Equatable {
        let isSecret: Bool
        let value: String?

        init(isSecret: Bool, value: String?) {
            self.isSecret = isSecret
            self.value = isSecret ? nil : value
        }
    }
}
