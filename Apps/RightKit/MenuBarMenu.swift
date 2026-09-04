import RightKitShared
import SwiftUI

/// The status-item dropdown: two commands, plus a warning line that only exists when
/// something is actually wrong.
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
