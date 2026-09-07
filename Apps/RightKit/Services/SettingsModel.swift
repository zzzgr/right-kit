import AppKit
import Combine
import RightKitShared
import SwiftUI

/// Observable face of ``Preferences`` for the settings window, plus the snapshot of
/// which terminals/editors are actually installed.
///
/// Both belong together: every control in the window either flips a preference or
/// picks from the installed list, and the pickers only ever offer apps that exist —
/// no greyed-out entries for software the user does not have.
@MainActor
final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    @Published private(set) var enabledActions: [MenuAction]
    @Published private(set) var installedTerminals: [TerminalApp] = []
    @Published private(set) var installedEditors: [EditorApp] = []

    @Published var preferredTerminal: TerminalApp? {
        didSet { preferences.preferredTerminal = preferredTerminal }
    }
    @Published var preferredEditor: EditorApp? {
        didSet { preferences.preferredEditor = preferredEditor }
    }

    /// Mirrors the system's Login Items entry (see ``LoginItem``). Writing flips the
    /// registration; if macOS refuses, the toggle snaps back and the reason is shown
    /// under it instead of a modal.
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLoginItem, launchAtLogin != LoginItem.isEnabled else { return }
            do {
                try LoginItem.setEnabled(launchAtLogin)
                loginItemError = nil
            } catch {
                loginItemError = Strings.launchAtLoginFailed
            }
            refreshLoginItem()
        }
    }
    @Published private(set) var loginItemState: LoginItem.State = .disabled
    @Published private(set) var loginItemError: String?
    private var isSyncingLoginItem = false

    private let preferences: Preferences
    private var activationObserver: NSObjectProtocol?

    private init(preferences: Preferences = .shared) {
        self.preferences = preferences
        enabledActions = preferences.enabledActions
        preferredTerminal = preferences.preferredTerminal
        preferredEditor = preferences.preferredEditor
        launchAtLogin = LoginItem.isEnabled
        refresh()

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Installing an editor and switching back should just show it.
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Re-read the installed apps. Called when the settings window opens and when the
    /// app is activated — the only freshness promised, and enough of it (no
    /// filesystem watching for something the user changes once a month).
    func refresh() {
        installedTerminals = TerminalApp.installed
        installedEditors = EditorApp.installed
        enabledActions = preferences.enabledActions
        refreshLoginItem()
    }

    /// Re-read the system's answer. Also called after each toggle, because macOS may
    /// park a fresh registration in `requiresApproval` rather than enabling it.
    private func refreshLoginItem() {
        loginItemState = LoginItem.state
        isSyncingLoginItem = true
        launchAtLogin = LoginItem.isEnabled
        isSyncingLoginItem = false
    }

    // MARK: - Menu contents

    func binding(for action: MenuAction) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.enabledActions.contains(action) ?? false },
            set: { [weak self] isOn in
                guard let self else { return }
                preferences.setEnabled(action, isOn)
                enabledActions = preferences.enabledActions
            }
        )
    }

    // MARK: - Resolved apps (what "Auto" currently means)

    var resolvedTerminal: TerminalApp? { TerminalApp.resolve(preferredTerminal) }
    var resolvedEditor: EditorApp? { EditorApp.resolve(preferredEditor) }
}
