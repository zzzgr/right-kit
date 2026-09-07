import Foundation

/// Where the menu-bar icon lands before the user chooses a position.
///
/// AppKit appends a status item that has no remembered position at the far *left* of
/// the third-party status area. Menu-bar managers (Ice, Bartender, Hidden Bar) keep
/// their hidden — or always-hidden — section exactly there, so on those machines a
/// fresh install shows no icon at all and the user concludes the app is broken.
///
/// Seed a moderate distance from the right edge so the icon sits with other apps
/// instead of between the system controls. The old 20-point seed is migrated once;
/// other saved positions, including subsequent user drags, are preserved.
enum StatusItemPlacement {
    /// SwiftUI's `MenuBarExtra` gives its `NSStatusItem` the autosave name `Item-0`
    /// (verified on macOS 15); AppKit persists the position under this key. If a future
    /// SwiftUI renames it, the seed becomes a harmless unused default.
    static let key = "NSStatusItem Preferred Position Item-0"

    static let preferredPosition = 360.0

    private static let legacyPreferredPosition = 20.0
    private static let migrationKey = "didMigrateStatusItemPlacement"

    /// Must run before the `MenuBarExtra` scene is built — i.e. from `App.init`.
    static func seedIfNeeded(defaults: UserDefaults = .standard) {
        let hasPosition = defaults.object(forKey: key) != nil
        let needsMigration = !defaults.bool(forKey: migrationKey)
            && defaults.double(forKey: key) == legacyPreferredPosition

        if !hasPosition || needsMigration {
            defaults.set(preferredPosition, forKey: key)
        }
        defaults.set(true, forKey: migrationKey)
    }
}
