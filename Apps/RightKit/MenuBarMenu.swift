import RightKitShared
import SwiftUI

/// Settings and Quit, with a warning only when the extension is off.
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
            AppWindows.settings.show()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(Strings.menuQuit) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
