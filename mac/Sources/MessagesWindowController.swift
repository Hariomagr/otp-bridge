import AppKit
import SwiftUI

/// Opens the email-style Messages window on demand. The app is a menu-bar
/// agent (LSUIElement), so we manage a real NSWindow here rather than a
/// SwiftUI WindowGroup, and flip to a regular activation policy while it's
/// visible so it can take focus and appear in the app switcher.
@MainActor
final class MessagesWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: MessagesView(model: model))
            let w = NSWindow(contentViewController: hosting)
            w.title = "OTP Bridge — Messages"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 820, height: 500))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // Back to menu-bar-only when the window closes.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
