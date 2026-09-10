import RightKitShared
import SwiftUI

/// AppKit-hosted windows, opened explicitly from the menu bar or setup flow.
@MainActor
enum AppWindows {
    /// First-run checklist. Also reachable from the main window and from the
    /// menu-bar warning when the extension gets switched off later.
    static let setup = HostedWindow(
        title: Strings.setupWindowTitle,
        autosaveName: "RightKitSetup",
        onUserClose: { Preferences.shared.didCompleteSetup = true },
        content: {
            SetupView()
                .environmentObject(SetupStatus.shared)
        }
    )

    /// The one main window: sidebar sections for general settings, the Finder
    /// menu, custom actions, the market and about. Opened through
    /// ``AppNavigation/show(_:)`` so callers land on the right section.
    static let main = HostedWindow(
        title: Strings.appName,
        autosaveName: "RightKitMain",
        style: .split,
        contentSize: NSSize(width: 1160, height: 760),
        minimumSize: MainWindowView.minimumSize,
        content: {
            MainWindowView()
                .environmentObject(SetupStatus.shared)
                .environmentObject(SettingsModel.shared)
                .environmentObject(CustomActionsModel.shared)
        }
    )
}
