import Foundation
import ServiceManagement

/// Launch-at-login, backed by `SMAppService` (macOS 13+).
///
/// The system owns this state, not `Preferences`: what the user sees in
/// System Settings → General → Login Items is the truth, and the app only mirrors
/// it. Registering needs no entitlement, no helper bundle and no prompt of its own —
/// macOS just lists the app under Login Items (and may show its own one-off
/// notification), which keeps the "one toggle and nothing else" promise intact.
@MainActor
enum LoginItem {
    enum State: Equatable {
        /// Registered and allowed to run.
        case enabled
        /// Registered, but the user has switched it off in System Settings
        /// ("Allow in the Background"). The toggle shows off plus a hint.
        case requiresApproval
        case disabled
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    static var isEnabled: Bool { state == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Apple's own entry point for the Login Items pane — used when macOS has parked
    /// the registration in `requiresApproval`.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
