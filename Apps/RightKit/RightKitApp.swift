import RightKitShared
import SwiftUI

@main
struct RightKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// The status item is the app's entire visible surface — no Dock icon, no main
    /// window, no app menu (`LSUIElement`). Windows are opened on demand from
    /// ``AppWindows``.
    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
                .environmentObject(SetupStatus.shared)
        } label: {
            Image("StatusItem")
                .renderingMode(.template)
                .accessibilityLabel(Strings.appName)
        }
        .menuBarExtraStyle(.menu)
    }
}
