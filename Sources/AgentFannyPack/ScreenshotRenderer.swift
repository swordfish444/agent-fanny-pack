import AppKit
import SwiftUI

@MainActor
enum ScreenshotRenderer {
    static func render(to url: URL, dark: Bool, showAllQuotas: Bool = false, fixture: String? = nil) throws {
        let model = fixture.map { AppModel(fixture: $0) } ?? AppModel(preview: true)
        model.setShowAllQuotaWindows(showAllQuotas)
        let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
        let content = PopoverView(model: model)
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height)
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

        // Render at 2x so the output is directly comparable with a Retina design
        // reference instead of being upscaled at comparison time.
        let scale = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(hosting.bounds.width) * scale,
            pixelsHigh: Int(hosting.bounds.height.rounded()) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = hosting.bounds.size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
        window.orderOut(nil)
    }
}
