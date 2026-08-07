import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private(set) var statusItem: NSStatusItem
    private(set) var popover: NSPopover
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popover = NSPopover()
        super.init()

        if let button = statusItem.button {
            button.image = StatusBarIcon.make()
            button.toolTip = "Agent Fanny Pack"
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentSize = NSSize(width: 440, height: 780)
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
        popover.delegate = self
    }

    @objc func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

private enum StatusBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { rect in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()

            let strap = NSBezierPath(roundedRect: NSRect(x: 1, y: 8, width: 17, height: 3), xRadius: 1.5, yRadius: 1.5)
            strap.fill()
            let pouch = NSBezierPath(roundedRect: NSRect(x: 4, y: 3, width: 11, height: 11), xRadius: 3, yRadius: 3)
            pouch.fill()

            NSColor.windowBackgroundColor.setStroke()
            let zipper = NSBezierPath()
            zipper.move(to: NSPoint(x: 6.2, y: 11.2))
            zipper.line(to: NSPoint(x: 12.8, y: 11.2))
            zipper.lineWidth = 1.2
            zipper.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Agent Fanny Pack"
        return image
    }
}
