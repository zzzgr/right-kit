import Foundation

/// Everything the Finder submenu can do.
///
/// One enum instead of a protocol + registry + parallel ID table: adding an action
/// means adding a case and letting the compiler point at the switches to fill in.
public enum MenuAction: String, CaseIterable, Sendable, Identifiable {
    case openInTerminal = "open.terminal"
    case openInEditor = "open.editor"
    case newFile = "new.file"
    case newFolder = "new.folder"
    case copyPath = "copy.path"

    public var id: String { rawValue }

    /// Stable label for settings — the Finder menu uses ``menuTitle(preferences:)``.
    public var settingsTitle: String {
        switch self {
        case .openInTerminal: return Strings.openInTerminal
        case .openInEditor: return Strings.openInEditor
        case .newFile: return Strings.newFile
        case .newFolder: return Strings.newFolder
        case .copyPath: return Strings.copyPath
        }
    }

    /// Finder menu label. Terminal/editor rows name the app that will actually
    /// open ("在 Ghostty 中打开") so the menu never lies about where you land.
    public func menuTitle(preferences: Preferences = .shared) -> String {
        switch self {
        case .openInTerminal:
            guard let app = TerminalApp.resolve(preferences.preferredTerminal) else {
                return Strings.openInTerminal
            }
            return Strings.openIn(app.displayName)
        case .openInEditor:
            guard let app = EditorApp.resolve(preferences.preferredEditor) else {
                return Strings.openInEditor
            }
            return Strings.openIn(app.displayName)
        case .newFile, .newFolder, .copyPath:
            return settingsTitle
        }
    }

    /// SF Symbol fallback. Terminal/editor rows prefer the real app icon
    /// (see ``iconAppURL(preferences:)``) and only fall back to this.
    public var symbolName: String {
        switch self {
        case .openInTerminal: return "terminal"
        case .openInEditor: return "chevron.left.forwardslash.chevron.right"
        case .newFile: return "doc.badge.plus"
        case .newFolder: return "folder.badge.plus"
        case .copyPath: return "link"
        }
    }

    /// Bundle of the app this action launches, when there is one — used to draw
    /// the real app icon in the Finder menu.
    public func iconAppURL(preferences: Preferences = .shared) -> URL? {
        switch self {
        case .openInTerminal:
            return TerminalApp.resolve(preferences.preferredTerminal)?.applicationURL
        case .openInEditor:
            return EditorApp.resolve(preferences.preferredEditor)?.applicationURL
        case .newFile, .newFolder, .copyPath:
            return nil
        }
    }

    /// Whether this action can run right now. Unavailable actions are *hidden*
    /// from the Finder menu rather than greyed out — a menu of things that work.
    public func isAvailable(in context: ActionContext, preferences: Preferences = .shared) -> Bool {
        switch self {
        case .openInTerminal:
            return context.workingDirectory != nil
                && TerminalApp.resolve(preferences.preferredTerminal) != nil
        case .openInEditor:
            return !context.targets.isEmpty
                && EditorApp.resolve(preferences.preferredEditor) != nil
        case .newFile, .newFolder:
            return context.creationDirectory != nil
        case .copyPath:
            return !context.targets.isEmpty
        }
    }

    /// The one action light enough to run inside the Finder extension itself;
    /// everything else is handed to the (non-sandboxed) main app.
    public var runsInExtension: Bool {
        self == .copyPath
    }
}
