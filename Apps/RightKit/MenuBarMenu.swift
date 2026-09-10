import RightKitShared
import SwiftUI

/// Menu-bar dropdown: a health line, the main-window sections, Quit.
struct MenuBarMenu: View {
    @EnvironmentObject private var status: SetupStatus

    var body: some View {
        if !status.extensionEnabled {
            Button("⚠︎ \(Strings.menuExtensionDisabled)") {
                AppWindows.setup.show()
            }
            Divider()
        }

        Button(Strings.menuSettings) {
            AppNavigation.shared.show(.general)
        }
        .keyboardShortcut(",", modifiers: .command)

        Button(Strings.menuOpenActions) {
            AppNavigation.shared.show(.actions)
        }

        Button(Strings.menuOpenMarket) {
            AppNavigation.shared.show(.market)
        }

        Divider()

        Button(Strings.menuQuit) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
