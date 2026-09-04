import Foundation

/// Failures the user might actually see. Each case knows both what went wrong
/// and where the user has to go to fix it — the `recovery` route is what turns a
/// dead-end notification into a one-click fix.
public enum RightKitError: LocalizedError, Equatable {
    /// Finder gave us nothing usable (empty sidebar menu, vanished folder…).
    case noTarget
    /// No terminal / editor installed (or the chosen one was removed).
    case appNotFound(kind: AppKind)
    /// The app is installed but refused to launch.
    case launchFailed(appName: String, reason: String)
    /// Write failed for a reason other than permissions.
    case createFailed(name: String, reason: String)
    /// macOS denied file access (TCC) — the one failure with a real fix.
    case accessDenied(folderName: String)
    case pasteboardFailed

    public enum AppKind: Sendable, Equatable {
        case terminal
        case editor

        var displayName: String {
            switch self {
            case .terminal: return Strings.terminalKind
            case .editor: return Strings.editorKind
            }
        }
    }

    /// Where the user should be sent to resolve this, if anywhere.
    public enum Recovery: Sendable, Equatable {
        /// System Settings → Privacy & Security → Files and Folders.
        case filesAndFolders
        /// RightKit's own settings (pick a different app).
        case appSettings
    }

    public var errorDescription: String? {
        switch self {
        case .noTarget:
            return Strings.errorNoTarget
        case .appNotFound(let kind):
            return Strings.errorAppNotFound(kind.displayName)
        case .launchFailed(let appName, let reason):
            return Strings.errorLaunchFailed(appName, reason)
        case .createFailed(let name, let reason):
            return Strings.errorCreateFailed(name, reason)
        case .accessDenied(let folderName):
            return Strings.errorAccessDenied(folderName)
        case .pasteboardFailed:
            return Strings.errorPasteboard
        }
    }

    public var recovery: Recovery? {
        switch self {
        case .accessDenied: return .filesAndFolders
        case .appNotFound: return .appSettings
        case .noTarget, .launchFailed, .createFailed, .pasteboardFailed: return nil
        }
    }

    /// Classifies a filesystem error: TCC denials and plain permission errors
    /// become ``accessDenied`` so the notification can offer the privacy pane.
    static func fromFileSystem(_ error: Error, name: String, directory: URL) -> RightKitError {
        let nsError = error as NSError
        let isPermission: Bool
        switch (nsError.domain, nsError.code) {
        case (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
             (NSCocoaErrorDomain, NSFileReadNoPermissionError):
            isPermission = true
        case (NSPOSIXErrorDomain, Int(EACCES)), (NSPOSIXErrorDomain, Int(EPERM)):
            isPermission = true
        default:
            // Cocoa wraps the POSIX error; look one level down too.
            let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            isPermission = underlying?.domain == NSPOSIXErrorDomain
                && (underlying?.code == Int(EACCES) || underlying?.code == Int(EPERM))
        }
        if isPermission {
            return .accessDenied(folderName: directory.lastPathComponent)
        }
        return .createFailed(name: name, reason: nsError.localizedFailureReason ?? nsError.localizedDescription)
    }
}
