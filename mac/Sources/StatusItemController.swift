import AppKit
import SwiftUI

/// Manages the menu-bar item ourselves (instead of SwiftUI's MenuBarExtra) so
/// the icon can animate: a little teal mascot that bobs and blinks. Clicking it
/// toggles a popover hosting the SwiftUI menu.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    private var frames: [NSImage] = []
    private var frameIndex = 0
    private var timer: Timer?

    init(rootView: some View) {
        super.init()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: rootView)

        statusItem.button?.imageScaling = .scaleNone
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        frames = StatusItemController.buildFrames()
        statusItem.button?.image = frames.first

        // ~12 fps loop; light enough for a menu-bar animation.
        let t = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        statusItem.button?.image = frames[frameIndex]
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Mascot frames

    private static func buildFrames() -> [NSImage] {
        let count = 12
        // A small side-to-side tremble — the mascot is a nervous little dog.
        let jitter: [CGFloat] = [0, 0.6, -0.5, 0.7, -0.6, 0.4, 0, -0.4, 0.5, -0.6, 0.5, -0.3]
        return (0..<count).map { i in
            mascotFrame(dx: jitter[i], blink: i == 5)
        }
    }

    /// Tiny worried pink dog (original mascot), matching the app icon art.
    private static func mascotFrame(dx: CGFloat, blink: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 20))
        img.lockFocus()

        let pink = NSColor(srgbRed: 0.94, green: 0.68, blue: 0.81, alpha: 1)
        let earPink = NSColor(srgbRed: 0.78, green: 0.42, blue: 0.60, alpha: 1)
        let dark = NSColor(srgbRed: 0.12, green: 0.10, blue: 0.16, alpha: 1)

        // Floppy ears.
        earPink.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2.5 + dx, y: 5, width: 3.5, height: 8)).fill()
        NSBezierPath(ovalIn: NSRect(x: 14 + dx, y: 5, width: 3.5, height: 8)).fill()

        // Head.
        pink.setFill()
        NSBezierPath(ovalIn: NSRect(x: 4 + dx, y: 5, width: 12, height: 11)).fill()

        // Eyes (blink = thin lids).
        for ex in [8.0, 12.0] {
            let x = ex + dx
            if blink {
                let lid = NSBezierPath()
                lid.move(to: NSPoint(x: x - 1.6, y: 11))
                lid.line(to: NSPoint(x: x + 1.6, y: 11))
                lid.lineWidth = 0.9
                dark.setStroke()
                lid.stroke()
            } else {
                NSColor.white.setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 1.7, y: 9.5, width: 3.4, height: 4.2)).fill()
                dark.setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 0.7, y: 10.2, width: 1.4, height: 1.4)).fill()
            }
        }

        // Nose.
        dark.setFill()
        NSBezierPath(ovalIn: NSRect(x: 9.2 + dx, y: 7, width: 1.6, height: 1.2)).fill()

        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}
