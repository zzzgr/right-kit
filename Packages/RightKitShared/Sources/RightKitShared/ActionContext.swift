import Foundation

/// What the user right-clicked, reduced to two facts: the items they picked and
/// the folder the menu was opened in. Every per-action directory is derived from
/// those two, identically in the extension and in the main app — which is why the
/// handoff URL only needs to carry these two fields.
public struct ActionContext: Sendable, Equatable {
    /// Selected items, or the right-clicked folder when nothing is selected.
    public let targets: [URL]
    /// The folder Finder had targeted, if any (nil for sidebar/toolbar menus).
    public let container: URL?

    public init(targets: [URL], container: URL?) {
        self.targets = targets
        self.container = container
    }

    /// Built from a Finder Sync selection snapshot.
    public init(selection: [URL], targetedURL: URL?) {
        let targets = selection.isEmpty ? [targetedURL].compactMap { $0 } : selection
        self.init(targets: targets, container: targetedURL)
    }

    public var isEmpty: Bool { targets.isEmpty && container == nil }

    /// Working directory for a terminal: the selected folder, the parent of the
    /// selected file, or the common parent of a multi-selection.
    public var workingDirectory: URL? {
        if targets.count == 1 {
            return directory(of: targets[0])
        }
        if targets.isEmpty {
            return container.map(directory(of:))
        }
        return commonParent(of: targets) ?? container ?? directory(of: targets[0])
    }

    /// Folder that New File / New Folder should write into. Prefers the
    /// right-clicked container so "new file" lands where the user is looking.
    public var creationDirectory: URL? {
        if let container {
            return directory(of: container)
        }
        if targets.count == 1 {
            return directory(of: targets[0])
        }
        return commonParent(of: targets)
    }

    // MARK: - Helpers

    private func directory(of url: URL) -> URL {
        PathUtilities.isDirectory(url) ? url : url.deletingLastPathComponent()
    }

    private func commonParent(of urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        let parent = first.deletingLastPathComponent().standardizedFileURL
        let allShare = urls.allSatisfy {
            $0.deletingLastPathComponent().standardizedFileURL.path == parent.path
        }
        return allShare ? parent : nil
    }
}
