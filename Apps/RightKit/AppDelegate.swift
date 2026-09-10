import AppKit
import RightKitShared
import os.log

private let log = Logger(subsystem: "com.rightkit.app", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = AppAppearance.shared
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
            AppNavigation.shared.show(.menu)
        } else {
            AppWindows.setup.show()
        }
        return false
    }

    /// `rightkit://run?…` from the Finder extension — the app half of the handoff.
    /// Success is deliberately silent; only failures speak (see ``Notifier``).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme?.lowercased() == "rightkit", ["import", "market"].contains(url.host?.lowercased() ?? "") {
                AppNavigation.shared.show(.actions)
                CustomActionsModel.shared.handleMarketLink(url)
                continue
            }
            if url.scheme?.lowercased() == ActionLink.scheme, url.host?.lowercased() == "custom" {
                CustomActionsModel.shared.runFinderRequest(url)
                continue
            }
            guard let request = ActionLink.request(from: url) else {
                log.notice("ignoring unrecognised URL")
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let actions = CustomActionsModel.shared
        guard actions.resolveUnsavedChanges() else { return .terminateCancel }
        guard actions.activeCount > 0 else { return .terminateNow }
        actions.cancelForQuit { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
