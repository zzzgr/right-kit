import AppKit
import Foundation

/// System Settings deep links. Modern pane identifiers first, older ones as
/// fallbacks, so the same call works across supported macOS versions.
///
/// The Finder-extension toggle is *not* here: the app opens it through
/// `FIFinderSyncController.showExtensionManagementInterface()`, which is Apple's
/// own entry point and lands on the right list.
public enum SystemSettings {
    /// Privacy & Security → Files and Folders — where a denied folder is re-allowed.
    public static func openFilesAndFolders() {
        open([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ])
    }

    @discardableResult
    private static func open(_ candidates: [String]) -> Bool {
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return true
            }
        }
        return false
    }
}
