import AppKit
import RightKitShared
import os.log

private let log = Logger(subsystem: "com.rightkit.app", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Notifier.shared.activate()
        SetupStatus.shared.refresh()

        // Setup opens itself exactly once — after that the menu-bar warning is the
        // way back in, so an app that is already working never nags.
        if !Preferences.shared.didCompleteSetup {
            AppWindows.setup.show()
        }
    }

    /// Reopened from Finder (double-clicking an already-running menu-bar app). Show
    /// something instead of appearing dead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SetupStatus.shared.refresh()
        if SetupStatus.shared.isReady {
            AppWindows.settings.show()
        } else {
            AppWindows.setup.show()
        }
        return false
    }

    /// `rightkit://run?…` from the Finder extension — the app half of the handoff.
    /// Success is deliberately silent; only failures speak (see ``Notifier``).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let request = ActionLink.request(from: url) else {
                log.notice("ignoring unrecognised url \(url.absoluteString, privacy: .public)")
                continue
            }
            do {
                try ActionRunner.run(request.action, in: request.context)
                log.notice("ran \(request.action.rawValue, privacy: .public)")
            } catch {
                Notifier.report(error, action: request.action)
            }
        }
    }
}
