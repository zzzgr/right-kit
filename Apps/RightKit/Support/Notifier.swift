import AppKit
import RightKitShared
import UserNotifications
import os.log

private let log = Logger(subsystem: "com.rightkit.app", category: "feedback")

/// Key under which a notification carries its recovery route to the click handler.
private let recoveryKey = "recovery"

/// Failure reporting, and only failure reporting.
///
/// A successful action needs no UI — the terminal window, the new file or the filled
/// clipboard *is* the feedback. A failure gets one notification that says what broke
/// and, when there is a fix, opens the right settings pane when clicked.
///
/// Notification permission is requested on the first failure, never at launch: an
/// app that asks for permission to talk before it has anything to say is noise.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var didRequestAuthorization = false

    private override init() { super.init() }

    /// Called once at launch so notification clicks reach ``userNotificationCenter(_:didReceive:withCompletionHandler:)``.
    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    static func report(_ error: Error, action: MenuAction) {
        let rightKitError = error as? RightKitError
        let body = rightKitError?.errorDescription ?? error.localizedDescription
        log.error("\(action.rawValue, privacy: .public) failed: \(body, privacy: .public)")
        shared.show(title: action.settingsTitle, body: body, recovery: rightKitError?.recovery)
    }

    private func show(title: String, body: String, recovery: RightKitError.Recovery?) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.deliver(title: title, body: body, recovery: recovery)
                case .notDetermined where !self.didRequestAuthorization:
                    self.didRequestAuthorization = true
                    let granted = try? await center.requestAuthorization(options: [.alert, .sound])
                    if granted == true {
                        self.deliver(title: title, body: body, recovery: recovery)
                    } else {
                        self.fallback(body)
                    }
                default:
                    self.fallback(body)
                }
            }
        }
    }

    private func deliver(title: String, body: String, recovery: RightKitError.Recovery?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let recovery {
            content.userInfo = [recoveryKey: recovery.rawIdentifier]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Notifications refused: beep so the click is not silently swallowed, and leave
    /// the detail in the log.
    private func fallback(_ body: String) {
        NSSound.beep()
        log.error("notifications unavailable, beeped instead: \(body, privacy: .public)")
    }

    // MARK: - Click routing

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content.userInfo[recoveryKey] as? String
        Task { @MainActor in
            switch raw.flatMap(RightKitError.Recovery.init(rawIdentifier:)) {
            case .filesAndFolders:
                SystemSettings.openFilesAndFolders()
            case .appSettings:
                AppWindows.settings.show()
            case nil:
                break
            }
            completionHandler()
        }
    }
}

private extension RightKitError.Recovery {
    var rawIdentifier: String {
        switch self {
        case .filesAndFolders: return "filesAndFolders"
        case .appSettings: return "appSettings"
        }
    }

    init?(rawIdentifier: String) {
        switch rawIdentifier {
        case "filesAndFolders": self = .filesAndFolders
        case "appSettings": self = .appSettings
        default: return nil
        }
    }
}
