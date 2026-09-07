import Foundation

/// Settings shared between the main app (writer) and the Finder extension (reader),
/// stored in the App Group so both processes see the same values.
///
/// Everything has a sane default, so a fresh install is fully usable without ever
/// opening the settings window.
public final class Preferences: @unchecked Sendable {
    /// macOS permits team-prefixed groups without a provisioning profile. A
    /// `group.` identifier needs registered membership and can otherwise trigger
    /// App Data privacy prompts. Both targets' entitlements must match this value.
    public static let appGroupID = "SAXZHR4HFD.com.rightkit.app"

    public static let shared = Preferences()

    enum Key {
        static let enabledActions = "enabledActions"
        static let preferredTerminal = "preferredTerminal"
        static let preferredEditor = "preferredEditor"
        static let didCompleteSetup = "didCompleteSetup"
    }

    let defaults: UserDefaults

    /// `suiteName: nil` (used by tests) keeps everything in a throwaway
    /// in-memory-ish standard domain instead of the shared group.
    public init(suiteName: String? = Preferences.appGroupID) {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            defaults = suite
        } else {
            defaults = .standard
        }
    }

    /// Pick up changes written by the other process (the app edits, the extension
    /// reads) before building a menu.
    public func reload() {
        defaults.synchronize()
    }

    // MARK: - Menu contents

    /// Actions the user wants in the Finder menu, in canonical order.
    ///
    /// Unset (fresh install) means "all of them". An explicitly empty list is
    /// honoured — turning everything off simply removes RightKit from the Finder
    /// menu, which is a legitimate thing to want and cheaper than a rule forbidding
    /// it.
    public var enabledActions: [MenuAction] {
        get {
            guard let stored = defaults.array(forKey: Key.enabledActions) as? [String] else {
                return MenuAction.allCases
            }
            let wanted = Set(stored)
            return MenuAction.allCases.filter { wanted.contains($0.rawValue) }
        }
        set {
            let ordered = MenuAction.allCases.filter(newValue.contains)
            defaults.set(ordered.map(\.rawValue), forKey: Key.enabledActions)
        }
    }

    public func isEnabled(_ action: MenuAction) -> Bool {
        enabledActions.contains(action)
    }

    public func setEnabled(_ action: MenuAction, _ enabled: Bool) {
        var actions = enabledActions
        actions.removeAll { $0 == action }
        if enabled { actions.append(action) }
        enabledActions = actions
    }

    // MARK: - Which app to open

    /// `nil` = Auto (first installed, see ``TerminalApp/autoOrder``).
    public var preferredTerminal: TerminalApp? {
        get { defaults.string(forKey: Key.preferredTerminal).flatMap(TerminalApp.init(rawValue:)) }
        set { setOptionalString(newValue?.rawValue, forKey: Key.preferredTerminal) }
    }

    /// `nil` = Auto (first installed, see ``EditorApp/autoOrder``).
    public var preferredEditor: EditorApp? {
        get { defaults.string(forKey: Key.preferredEditor).flatMap(EditorApp.init(rawValue:)) }
        set { setOptionalString(newValue?.rawValue, forKey: Key.preferredEditor) }
    }

    // MARK: - Setup

    /// Whether the user has dismissed the setup window at least once. Only decides
    /// if setup auto-opens at launch — never whether actions work.
    public var didCompleteSetup: Bool {
        get { defaults.bool(forKey: Key.didCompleteSetup) }
        set { defaults.set(newValue, forKey: Key.didCompleteSetup) }
    }

    private func setOptionalString(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
