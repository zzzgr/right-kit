import AppKit
import FinderSync
import RightKitShared
import os.log

private let log = Logger(subsystem: "com.rightkit.app.FinderSync", category: "menu")

/// The Finder half of RightKit: build a submenu, hand the click to the main app.
///
/// Three platform facts drive the shape of this file — all three were learned the
/// hard way and are load-bearing:
///
/// 1. Returning a flat menu makes Finder splice the items into its own context menu.
///    One parent item with a submenu is what produces "右键助手 ▸".
/// 2. Finder strips `representedObject` from menu items, so the clicked action is
///    resolved by `tag` against the snapshot taken when the menu was built.
/// 3. This process is sandboxed and can be suspended the moment a menu handler
///    returns — so anything heavier than a clipboard write is handed to the app.
final class FinderSyncExtension: FIFinderSync {
    private let preferences = Preferences.shared

    /// Snapshot from the last `menu(for:)` — see fact 2 above.
    private var menuActions: [MenuAction] = []
    private var menuContext = ActionContext(targets: [], container: nil)

    private var volumeObservers: [NSObjectProtocol] = []
    private var appIconCache: [String: NSImage] = [:]

    override init() {
        super.init()
        refreshMonitoredDirectories()
        observeVolumeChanges()
        // Tell the main app we exist: this is what turns setup's "试一试" step green
        // and proves the App Group is really shared. See ExtensionHeartbeat.
        // `Bundle.main` is the appex bundle here, and `object(forInfoDictionaryKey:)`
        // is the accessor that also resolves localized Info.plist values.
        ExtensionCheckIn.recordLoad(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
        log.notice("RightKit FinderSync loaded pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in volumeObservers {
            center.removeObserver(observer)
        }
    }

    // MARK: - Monitored directories

    private func observeVolumeChanges() {
        let center = NSWorkspace.shared.notificationCenter
        volumeObservers = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshMonitoredDirectories()
            }
        }
    }

    /// "/" alone does not reach other mounted filesystems, so home and every mounted
    /// volume are listed explicitly and refreshed on mount/unmount.
    private func refreshMonitoredDirectories() {
        let fileManager = FileManager.default
        var urls: Set<URL> = [URL(fileURLWithPath: "/"), fileManager.homeDirectoryForCurrentUser]
        if let volumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) {
            urls.formUnion(volumes)
        }
        FIFinderSyncController.default().directoryURLs = urls
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let root = NSMenu(title: "")

        preferences.reload()
        let controller = FIFinderSyncController.default()
        let context = ActionContext(
            selection: controller.selectedItemURLs() ?? [],
            targetedURL: controller.targetedURL()
        )
        // Only offer what can actually run: no editor installed, no editor row.
        let actions = preferences.enabledActions.filter {
            $0.isAvailable(in: context, preferences: preferences)
        }

        menuContext = context
        menuActions = actions
        ExtensionCheckIn.recordMenu(preferences: preferences)

        log.notice("menu kind=\(menuKind.rawValue) targets=\(context.targets.count) actions=\(actions.count)")

        // Nothing usable here: contribute no item at all rather than an empty
        // or all-greyed-out submenu.
        guard !actions.isEmpty else { return root }

        let submenu = NSMenu(title: Strings.appName)
        for (index, action) in actions.enumerated() {
            let item = NSMenuItem(
                title: action.menuTitle(preferences: preferences),
                action: #selector(performMenuAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.image = icon(for: action)
            submenu.addItem(item)
        }

        let parent = NSMenuItem(title: Strings.appName, action: nil, keyEquivalent: "")
        parent.image = brandGlyph
        parent.submenu = submenu
        root.addItem(parent)
        return root
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard menuActions.indices.contains(sender.tag) else {
            log.error("unresolved menu item tag=\(sender.tag)")
            return
        }
        let action = menuActions[sender.tag]

        // Re-read the selection: the user may have changed it between the menu
        // being built and the click landing.
        let controller = FIFinderSyncController.default()
        let fresh = ActionContext(
            selection: controller.selectedItemURLs() ?? [],
            targetedURL: controller.targetedURL()
        )
        let context = fresh.isEmpty ? menuContext : fresh

        if action.runsInExtension {
            do {
                try ActionRunner.run(action, in: context, preferences: preferences)
                return
            } catch {
                log.error(
                    "\(action.rawValue, privacy: .public) failed in extension: \(error.localizedDescription, privacy: .public)"
                )
                // Fall through: let the main app retry and report properly.
            }
        }

        let request = ActionLink.Request(action: action, context: context)
        if ActionLink.handOff(request) {
            log.notice("handed off \(action.rawValue, privacy: .public)")
        } else {
            log.error("handoff failed for \(action.rawValue, privacy: .public)")
            NSSound.beep()
        }
    }

    // MARK: - Icons

    /// The RightKit glyph next to the parent row. The asset catalogue carries 1× and 2×;
    /// asking for a 16pt size lets AppKit pick the sharp one.
    private lazy var brandGlyph: NSImage? = {
        let image = NSImage(named: "MenuIcon")
            ?? NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: nil)
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
    }()

    /// Rows that launch an app show that app's real icon — the menu then says both
    /// "in Ghostty" and *looks* like Ghostty. Everything else uses an SF Symbol.
    ///
    /// Icons are cached: a right-click must feel instant, and reading an `.icns` off
    /// disk on every menu build is the one avoidable cost here.
    private func icon(for action: MenuAction) -> NSImage? {
        if let applicationURL = action.iconAppURL(preferences: preferences) {
            if let cached = appIconCache[applicationURL.path] { return cached }
            let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
            icon.size = NSSize(width: 16, height: 16)
            appIconCache[applicationURL.path] = icon
            return icon
        }
        let image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        image?.isTemplate = true
        return image
    }
}
