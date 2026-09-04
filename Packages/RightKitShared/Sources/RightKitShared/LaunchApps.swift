import AppKit
import Foundation

// MARK: - Terminals

/// Terminals we know how to open a folder in.
///
/// All of them declare a folder document type (`public.directory` / OSType `fold`),
/// so `NSWorkspace.open(folder, withApplicationAt:)` lands in the right directory.
/// That is deliberate: it means RightKit needs **no Automation (Apple Events)
/// permission at all** — no AppleScript, no TCC prompt, no "allow controlling
/// Terminal" step in setup.
public enum TerminalApp: String, CaseIterable, Sendable, Identifiable {
    case iterm2
    case ghostty
    case terminal

    public var id: String { rawValue }

    /// Order used by "Auto": nicer terminals first, Terminal.app as the one that
    /// is always installed.
    public static let autoOrder: [TerminalApp] = [.iterm2, .ghostty, .terminal]

    public var displayName: String {
        switch self {
        case .iterm2: return "iTerm2"
        case .ghostty: return "Ghostty"
        case .terminal: return "Terminal"
        }
    }

    public var bundleIdentifiers: [String] {
        switch self {
        case .iterm2: return ["com.googlecode.iterm2"]
        case .ghostty: return ["com.mitchellh.ghostty"]
        case .terminal: return ["com.apple.Terminal"]
        }
    }

    public var applicationURL: URL? { AppLauncher.applicationURL(for: bundleIdentifiers) }

    public var isInstalled: Bool { applicationURL != nil }

    public static var installed: [TerminalApp] { autoOrder.filter(\.isInstalled) }

    /// `nil` preference means Auto. A preference pointing at an app that is no
    /// longer installed also falls back to Auto, so settings can never strand
    /// the menu item.
    public static func resolve(_ preferred: TerminalApp?) -> TerminalApp? {
        if let preferred, preferred.isInstalled { return preferred }
        return installed.first
    }
}

// MARK: - Editors

/// Editors that open a folder or file passed by LaunchServices.
public enum EditorApp: String, CaseIterable, Sendable, Identifiable {
    case vsCode
    case cursor
    case zed
    case sublimeText

    public var id: String { rawValue }

    public static let autoOrder: [EditorApp] = [.vsCode, .cursor, .zed, .sublimeText]

    public var displayName: String {
        switch self {
        case .vsCode: return "VS Code"
        case .cursor: return "Cursor"
        case .zed: return "Zed"
        case .sublimeText: return "Sublime Text"
        }
    }

    public var bundleIdentifiers: [String] {
        switch self {
        case .vsCode: return ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
        case .cursor: return ["com.todesktop.230313mzl4w4u92"]
        case .zed: return ["dev.zed.Zed", "dev.zed.Zed-Preview"]
        case .sublimeText: return ["com.sublimetext.4", "com.sublimetext.3"]
        }
    }

    public var applicationURL: URL? { AppLauncher.applicationURL(for: bundleIdentifiers) }

    public var isInstalled: Bool { applicationURL != nil }

    public static var installed: [EditorApp] { autoOrder.filter(\.isInstalled) }

    public static func resolve(_ preferred: EditorApp?) -> EditorApp? {
        if let preferred, preferred.isInstalled { return preferred }
        return installed.first
    }
}

// MARK: - Launching

/// The only place that talks to LaunchServices.
public enum AppLauncher {
    public static func applicationURL(for bundleIdentifiers: [String]) -> URL? {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        return nil
    }

    /// Opens `urls` with the app at `applicationURL`.
    ///
    /// Synchronous by necessity: callers may be a Finder Sync menu handler, whose
    /// process can be suspended the moment the handler returns. A launch that is
    /// still pending after the timeout is treated as success — NSWorkspace often
    /// reports late, and the window does appear.
    public static func open(_ urls: [URL], withApplicationAt applicationURL: URL, appName: String) throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let group = DispatchGroup()
        group.enter()
        var launchError: Error?
        NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: configuration) { _, error in
            launchError = error
            group.leave()
        }
        guard group.wait(timeout: .now() + 5) == .success else { return }
        if let launchError {
            throw RightKitError.launchFailed(appName: appName, reason: launchError.localizedDescription)
        }
    }
}
