import AppKit
import SwiftUI

@MainActor
enum ScreenshotRenderer {
    static func render(to url: URL, dark: Bool, showAllQuotas: Bool = false) throws {
        let model = AppModel(preview: true)
        model.setShowAllQuotaWindows(showAllQuotas)
        let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
        let content = PopoverView(model: model)
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 440, height: 690)
        hosting.appearance = NSAppearance(named: appearance)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.appearance = hosting.appearance
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
        window.orderOut(nil)
    }
}
