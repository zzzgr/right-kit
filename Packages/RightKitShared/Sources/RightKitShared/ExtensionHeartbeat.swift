import Foundation

/// The Finder extension checking in.
///
/// macOS gives the containing app no way to *prove* its Finder extension works —
/// `FIFinderSyncController.isExtensionEnabled` reports the system toggle, not
/// reality. So the extension leaves a trace in the App Group every time it is
/// loaded and every time it actually builds a menu. That single timestamp does
/// three jobs at once:
///
/// 1. setup can show a real "✓ 已在 Finder 中检测到" instead of a hopeful guess;
/// 2. it corroborates the system toggle (a fresh load right after the user flips
///    the switch means "on", whatever the API says);
/// 3. it proves the App Group is genuinely shared between the two processes —
///    if it were not, nothing would ever arrive.
public struct ExtensionHeartbeat: Sendable, Equatable {
    /// When the extension process was last started by Finder.
    public let loadedAt: Date?
    /// When the extension last built a context menu.
    public let lastMenuAt: Date?
    /// Extension bundle version, to spot a stale copy left behind by an old build.
    public let version: String?

    public static let none = ExtensionHeartbeat(loadedAt: nil, lastMenuAt: nil, version: nil)

    /// The extension has demonstrably run in Finder at least once.
    public var didServeMenu: Bool { lastMenuAt != nil }

    /// The extension reported in at all (⇒ the App Group really is shared).
    public var didReport: Bool { loadedAt != nil || lastMenuAt != nil }

    /// Loaded (or used) just now — strong evidence the extension is live even if
    /// the system toggle has not been re-read yet.
    public func isLive(now: Date = Date(), within window: TimeInterval = 300) -> Bool {
        let latest = [loadedAt, lastMenuAt].compactMap { $0 }.max()
        guard let latest else { return false }
        return now.timeIntervalSince(latest) < window && latest <= now.addingTimeInterval(60)
    }
}

/// Read/write side of ``ExtensionHeartbeat``.
public enum ExtensionCheckIn {
    enum Key {
        static let loadedAt = "extension.loadedAt"
        static let lastMenuAt = "extension.lastMenuAt"
        static let version = "extension.version"
    }

    /// Don't rewrite the menu timestamp on every single right-click.
    private static let menuWriteInterval: TimeInterval = 30
    private static let lock = NSLock()
    private static var lastMenuWrite: Date?

    /// Called from the extension's initialiser.
    public static func recordLoad(version: String?, preferences: Preferences = .shared) {
        preferences.defaults.set(Date().timeIntervalSince1970, forKey: Key.loadedAt)
        // Always written, even when unknown: a missing key would otherwise be
        // indistinguishable from an extension that never checked in.
        preferences.defaults.set(version ?? "unknown", forKey: Key.version)
    }

    /// Called from the extension every time Finder asks for a menu.
    public static func recordMenu(preferences: Preferences = .shared) {
        let now = Date()
        lock.lock()
        let shouldWrite = lastMenuWrite.map { now.timeIntervalSince($0) >= menuWriteInterval } ?? true
        if shouldWrite { lastMenuWrite = now }
        lock.unlock()
        guard shouldWrite else { return }
        preferences.defaults.set(now.timeIntervalSince1970, forKey: Key.lastMenuAt)
    }

    /// Called from the main app.
    public static func read(preferences: Preferences = .shared) -> ExtensionHeartbeat {
        // Values arrive from another process; ask for a fresh read.
        preferences.defaults.synchronize()
        return ExtensionHeartbeat(
            loadedAt: date(preferences.defaults.double(forKey: Key.loadedAt)),
            lastMenuAt: date(preferences.defaults.double(forKey: Key.lastMenuAt)),
            version: preferences.defaults.string(forKey: Key.version)
        )
    }

    /// Forget the recorded evidence — used by "重新引导" so the setup checklist
    /// verifies the current build instead of showing a stale ✓.
    public static func reset(preferences: Preferences = .shared) {
        for key in [Key.loadedAt, Key.lastMenuAt, Key.version] {
            preferences.defaults.removeObject(forKey: key)
        }
        lock.lock()
        lastMenuWrite = nil
        lock.unlock()
    }

    private static func date(_ timestamp: Double) -> Date? {
        timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }
}
