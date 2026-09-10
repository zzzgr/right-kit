import AppKit
import SwiftUI

/// A plain `NSWindow` hosting a SwiftUI view, sized by its content.
///
/// RightKit's windows use this instead of SwiftUI `Settings`/`Window` scenes.
/// In a menu-bar-only app (`LSUIElement`) those scenes cannot be opened imperatively
/// from AppKit, and reaching the Settings scene means sending a private selector that
/// SwiftUI has already objected to once. One small helper removes that whole class of
/// version-dependent breakage.
@MainActor
final class HostedWindow: NSObject, NSWindowDelegate {
    /// How the window chrome is drawn.
    enum Style {
        /// Fixed-size panel sized by its content (setup).
        case panel
        /// Resizable window with a unified toolbar so a `NavigationSplitView`
        /// sidebar extends into the title bar, like System Settings.
        case split
    }

    private let title: String
    private let autosaveName: String
    private let style: Style
    private let onUserClose: (() -> Void)?
    private let contentSize: NSSize?
    private let minimumSize: NSSize?
    private let makeContentController: () -> NSViewController

    private var window: NSWindow?

    /// `onUserClose` fires only when the *user* closes the window (red button, ⌘W) —
    /// `NSWindow.close()` skips `windowShouldClose(_:)`, so quitting the app or closing
    /// programmatically does not count as the user having dismissed anything.
    init<Content: View>(
        title: String,
        autosaveName: String,
        style: Style = .panel,
        onUserClose: (() -> Void)? = nil,
        contentSize: NSSize? = nil,
        minimumSize: NSSize? = nil,
        content: @escaping () -> Content
    ) {
        self.title = title
        self.autosaveName = autosaveName
        self.style = style
        self.onUserClose = onUserClose
        self.contentSize = contentSize
        self.minimumSize = minimumSize
        self.makeContentController = {
            let controller = NSHostingController(rootView: content().tint(.blue))
            // Keep the view's minimum size enforced without adopting a pane's
            // preferred height or maximum size when switching sections.
            if minimumSize != nil { controller.sizingOptions = [.minSize] }
            return controller
        }
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window: NSWindow
        switch style {
        case .panel:
            // Sized by its SwiftUI content.
            window = NSWindow(contentViewController: makeContentController())
            window.styleMask = [.titled, .closable]
            if minimumSize != nil { window.styleMask.insert([.resizable, .miniaturizable]) }
        case .split:
            // Chrome first, content second: SwiftUI measures its safe area when the
            // hosting view is installed, so a toolbar added afterwards would leave
            // the first layout tucked under the title bar. The (empty) toolbar is
            // what lets SwiftUI draw the sidebar full height and add its own
            // sidebar toggle; the unified style keeps the title bar compact.
            window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize ?? NSSize(width: 960, height: 640)),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
            let toolbar = NSToolbar(identifier: "\(autosaveName).toolbar")
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            window.contentViewController = makeContentController()
        }
        window.title = title
        if let contentSize { window.setContentSize(contentSize) }
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName(autosaveName)
        let restoredFrame = window.setFrameUsingName(autosaveName)
        if let minimumSize {
            window.contentMinSize = minimumSize
            // A frame saved by an older version can be smaller than today's minimum.
            let size = window.contentRect(forFrameRect: window.frame).size
            if size.width < minimumSize.width || size.height < minimumSize.height {
                window.setContentSize(NSSize(width: max(size.width, minimumSize.width),
                                             height: max(size.height, minimumSize.height)))
            }
        }
        if !restoredFrame { window.center() }
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func close() {
        window?.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onUserClose?()
        return true
    }
}
