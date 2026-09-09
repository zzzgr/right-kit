import RightKitShared
import SwiftUI

/// AppKit-hosted windows, opened explicitly from the menu bar or setup flow.
@MainActor
enum AppWindows {
    /// First-run checklist. Also reachable from settings and from the menu-bar
    /// warning when the extension gets switched off later.
    static let setup = HostedWindow(
        title: Strings.setupWindowTitle,
        autosaveName: "RightKitSetup",
        onUserClose: { Preferences.shared.didCompleteSetup = true },
        content: {
            SetupView()
                .environmentObject(SetupStatus.shared)
        }
    )

    static let settings = HostedWindow(
        title: Strings.appName,
        autosaveName: "RightKitSettings",
        content: {
            SettingsView()
                .environmentObject(SettingsModel.shared)
                .environmentObject(SetupStatus.shared)
        }
    )

    static let actions = HostedWindow(
        title: Strings.Custom.title,
        autosaveName: "RightKitCustomActions",
        contentSize: NSSize(width: 1100, height: 760),
        minimumSize: CustomActionsView.minimumWindowSize,
        content: {
            CustomActionsView()
                .environmentObject(CustomActionsModel.shared)
        }
    )
}
