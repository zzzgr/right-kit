import AppKit
import SwiftUI

/// A plain `NSWindow` hosting a SwiftUI view, sized by its content.
///
/// Both of RightKit's windows use this instead of SwiftUI `Settings`/`Window` scenes.
/// In a menu-bar-only app (`LSUIElement`) those scenes cannot be opened imperatively
/// from AppKit, and reaching the Settings scene means sending a private selector that
/// SwiftUI has already objected to once. One small helper removes that whole class of
/// version-dependent breakage.
@MainActor
final class HostedWindow: NSObject, NSWindowDelegate {
    private let title: String
    private let autosaveName: String
    private let onUserClose: (() -> Void)?
    private let makeContentController: () -> NSViewController

    private var window: NSWindow?

    /// `onUserClose` fires only when the *user* closes the window (red button, ⌘W) —
    /// `NSWindow.close()` skips `windowShouldClose(_:)`, so quitting the app or closing
    /// programmatically does not count as the user having dismissed anything.
    init<Content: View>(
        title: String,
        autosaveName: String,
        onUserClose: (() -> Void)? = nil,
        content: @escaping () -> Content
    ) {
        self.title = title
        self.autosaveName = autosaveName
        self.onUserClose = onUserClose
        self.makeContentController = { NSHostingController(rootView: content()) }
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentViewController: makeContentController())
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName(autosaveName)
        window.center()
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
