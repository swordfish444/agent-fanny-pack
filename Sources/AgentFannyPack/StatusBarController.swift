import AppKit
import SwiftUI
import AgentFannyPackCore

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private(set) var statusItem: NSStatusItem
    private(set) var popover: NSPopover
    private let model: AppModel

    /// Stable key so the position the user drags the item to survives relaunches, and so
    /// `MenuBarPlacement` has a preference to write when it has to rescue the item.
    static let autosaveName = "AgentFannyPack"

    init(model: AppModel) {
        self.model = model
        self.statusItem = Self.makeStatusItem()
        self.popover = NSPopover()
        super.init()

        configureButton()

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentSize = NSSize(width: Metrics.width, height: Metrics.height)
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
        popover.delegate = self

        // AppKit has not laid the item out yet; measure on the next pass.
        DispatchQueue.main.async { [weak self] in
            self?.rescueFromNotchIfNeeded(attempt: 0)
        }
    }

    private static func makeStatusItem() -> NSStatusItem {
        // `squareLength` reserves a full menu-bar-height square (38pt) for a 19pt glyph.
        // Those wasted points matter on a crowded bar, so ask only for what the art needs.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        return item
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = StatusBarIcon.make()
        button.toolTip = "Agent Fanny Pack"
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// The macOS menu bar has no overflow UI. When it is full, the system parks the newest
    /// status item under the notch of a built-in display: `isVisible` stays `true`, the frame
    /// is on screen, and nothing is ever composited — the app reads as installed and broken.
    /// Detect that and reseat the item in the region to the right of the camera housing.
    private func rescueFromNotchIfNeeded(attempt: Int) {
        guard attempt < MenuBarPlacement.maxAttempts else { return }
        guard let window = statusItem.button?.window,
              let screen = window.screen ?? NSScreen.main,
              MenuBarPlacement.isOccludedByNotch(frame: window.frame, on: screen) else { return }

        MenuBarPlacement.storePreferredPosition(
            MenuBarPlacement.preferredPosition(forAttempt: attempt),
            autosaveName: Self.autosaveName
        )

        // A stored preferred position is only consulted when the item is created, so rebuild it.
        NSStatusBar.system.removeStatusItem(statusItem)
        statusItem = Self.makeStatusItem()
        configureButton()

        DispatchQueue.main.asyncAfter(deadline: .now() + MenuBarPlacement.settleDelay) { [weak self] in
            self?.rescueFromNotchIfNeeded(attempt: attempt + 1)
        }
    }

    @objc func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        // Cheap local re-check so a sign-in completed in the provider's own app shows up
        // the next time the pouch is opened, without any polling.
        model.reconcilePendingConnections()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        keepOnScreen()
    }

    func popoverDidShow(_ notification: Notification) {
        keepOnScreen()
    }

    /// A status item near the edge of the display leaves AppKit anchoring this panel so it
    /// runs off the screen and loses its trailing column. Nudging the window back inside
    /// after it is on screen keeps the whole panel reachable; the arrow then sits off-centre
    /// from the status item, which is the right trade.
    private func keepOnScreen() {
        guard let window = popover.contentViewController?.view.window,
              let screen = window.screen ?? NSScreen.main else { return }
        var frame = window.frame
        frame.origin.x = ScreenPlacement.constrainedOriginX(panel: frame, within: screen.frame)
        guard frame.origin.x != window.frame.origin.x else { return }
        window.setFrame(frame, display: true)
    }

}

enum MenuBarPlacement {
    static let maxAttempts = 5
    static let settleDelay: TimeInterval = 0.4

    /// Each retry asks for a slot further from the right edge, stepping past whatever
    /// neighbours already hold the near-notch positions.
    static func preferredPosition(forAttempt attempt: Int) -> Int {
        180 + attempt * 160
    }

    static func storePreferredPosition(_ position: Int, autosaveName: String) {
        UserDefaults.standard.set(position, forKey: "NSStatusItem Preferred Position \(autosaveName)")
    }

    /// The notch is the gap between the two auxiliary top areas. Displays without one report
    /// no gap, so this returns `false` and the item is left exactly where the system put it.
    ///
    /// Only an item that actually overlaps the housing counts as occluded. The area to the
    /// left of the notch is perfectly visible, so an item the user dragged there is left alone.
    static func isOccludedByNotch(frame: NSRect, on screen: NSScreen) -> Bool {
        guard #available(macOS 12.0, *),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return false }
        let notch = NSRect(
            x: left.maxX,
            y: right.minY,
            width: right.minX - left.maxX,
            height: right.height
        )
        return frame.intersects(notch)
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
