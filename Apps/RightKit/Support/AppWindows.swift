import RightKitShared
import SwiftUI

/// The app's two windows. Kept together so "which windows exist?" has a one-screen
/// answer — there are exactly two, and neither is ever open unless the user asked.
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
}
