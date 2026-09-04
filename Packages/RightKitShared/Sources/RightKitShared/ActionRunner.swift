import AppKit
import Foundation

/// Performs a ``MenuAction``. Synchronous and throwing: the caller is either the
/// main app (which turns a thrown error into a notification) or, for copy-path, the
/// Finder extension, whose menu handler cannot wait for async work.
public enum ActionRunner {
    public static func run(
        _ action: MenuAction,
        in context: ActionContext,
        preferences: Preferences = .shared
    ) throws {
        switch action {
        case .openInTerminal:
            try openInTerminal(context, preferences)
        case .openInEditor:
            try openInEditor(context, preferences)
        case .newFile:
            try create(isDirectory: false, in: context)
        case .newFolder:
            try create(isDirectory: true, in: context)
        case .copyPath:
            try copyPath(context)
        }
    }

    // MARK: - Open

    private static func openInTerminal(_ context: ActionContext, _ preferences: Preferences) throws {
        guard let directory = context.workingDirectory else { throw RightKitError.noTarget }
        guard let app = TerminalApp.resolve(preferences.preferredTerminal),
              let applicationURL = app.applicationURL
        else { throw RightKitError.appNotFound(kind: .terminal) }

        try AppLauncher.open([directory], withApplicationAt: applicationURL, appName: app.displayName)
    }

    private static func openInEditor(_ context: ActionContext, _ preferences: Preferences) throws {
        let targets = context.targets
        guard !targets.isEmpty else { throw RightKitError.noTarget }
        guard let app = EditorApp.resolve(preferences.preferredEditor),
              let applicationURL = app.applicationURL
        else { throw RightKitError.appNotFound(kind: .editor) }

        try AppLauncher.open(targets, withApplicationAt: applicationURL, appName: app.displayName)
    }

    // MARK: - Create

    private static func create(isDirectory: Bool, in context: ActionContext) throws {
        guard let directory = context.creationDirectory else { throw RightKitError.noTarget }

        let baseName = isDirectory ? Strings.defaultFolderName : Strings.defaultFileName
        let url = PathUtilities.uniqueURL(in: directory, baseName: baseName, isDirectory: isDirectory)
        do {
            if isDirectory {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            } else {
                try Data().write(to: url, options: .withoutOverwriting)
            }
        } catch {
            // A denial here is the one failure with a real fix (Privacy → Files and
            // Folders), so classify instead of dumping a raw NSError on the user.
            throw RightKitError.fromFileSystem(error, name: url.lastPathComponent, directory: directory)
        }
        // Selecting the new item is the only feedback these two actions need.
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Copy

    private static func copyPath(_ context: ActionContext) throws {
        let paths = context.targets.map(\.path)
        guard !paths.isEmpty else { throw RightKitError.noTarget }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        guard pasteboard.setString(paths.joined(separator: "\n"), forType: .string) else {
            throw RightKitError.pasteboardFailed
        }
    }
}
