import AppKit
import Combine
import FinderSync
import RightKitShared

/// Everything setup needs to know, in one observable place: where the app lives,
/// whether the Finder extension is switched on, and whether it has ever actually
/// run. Setup, settings and the menu bar all read this — there is no second opinion.
///
/// Two signals are combined on purpose. `FIFinderSyncController.isExtensionEnabled`
/// reports the system toggle but can lag or misreport; the extension's own check-in
/// (``ExtensionHeartbeat``) is proof. Either one counts as "on", so a stale API read
/// can never leave the user staring at a warning about something that demonstrably
/// works.
@MainActor
final class SetupStatus: ObservableObject {
    static let shared = SetupStatus()

    enum Location: Equatable {
        /// In /Applications or ~/Applications — where extensions register reliably.
        case applications
        /// Still inside the mounted DMG. Nothing will work from here for long.
        case diskImage
        /// Downloads, Desktop, a build folder… works, but often not across reboots.
        case elsewhere(String)

        var isFine: Bool { self == .applications }
    }

    @Published private(set) var location: Location = .applications
    @Published private(set) var extensionEnabled = false
    @Published private(set) var heartbeat: ExtensionHeartbeat = .none

    /// The extension has served a menu at least once — the only end-to-end proof
    /// that the whole chain works.
    var isVerified: Bool { heartbeat.didServeMenu }

    /// Nothing left for the user to do.
    var isReady: Bool { location.isFine && extensionEnabled && isVerified }

    private let preferences: Preferences
    private var pollTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    /// Windows currently interested in live updates. A counter, not a flag: settings
    /// and setup can be open at once, and closing one must not stop the other's polling.
    private var watchers = 0

    private init(preferences: Preferences = .shared) {
        self.preferences = preferences
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Coming back from System Settings is the moment the answer changes.
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Refresh

    func refresh() {
        location = Self.currentLocation()
        heartbeat = ExtensionCheckIn.read(preferences: preferences)
        extensionEnabled = FIFinderSyncController.isExtensionEnabled || heartbeat.isLive()
    }

    /// Start/stop the 1s poll that makes the checklist tick itself. Cheap: one
    /// framework call plus one defaults read, no subprocess.
    func addWatcher() {
        watchers += 1
        guard pollTask == nil else { return }
        refresh()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.refresh()
            }
        }
    }

    func removeWatcher() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Actions

    /// Apple's own entry point for the Finder-extension list. Setup also spells out
    /// the manual path, so a button that lands on the wrong pane is not a dead end.
    func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// Used by "重新打开设置向导": drop the recorded proof so the checklist re-verifies
    /// the build that is running now instead of showing a ✓ earned by an old copy.
    func resetVerification() {
        ExtensionCheckIn.reset(preferences: preferences)
        refresh()
    }

    private static func currentLocation() -> Location {
        let bundleURL = Bundle.main.bundleURL
        let path = bundleURL.resolvingSymlinksInPath().path
        if path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/") {
            return .applications
        }
        // A read-only volume under /Volumes is, in practice, the mounted DMG the user
        // just downloaded — worth its own wording. A writable external disk is just
        // another "not in Applications" location.
        if path.hasPrefix("/Volumes/"), isOnReadOnlyVolume(bundleURL) {
            return .diskImage
        }
        let parent = bundleURL.deletingLastPathComponent()
        return .elsewhere(FileManager.default.displayName(atPath: parent.path))
    }

    private static func isOnReadOnlyVolume(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
    }
}
