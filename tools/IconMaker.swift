import AppKit
import Foundation

@main
struct IconMaker {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: icon-maker OUTPUT.png\n".utf8))
            exit(2)
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1024,
            pixelsHigh: 1024,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()

        let background = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 220, yRadius: 220)
        NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.13, alpha: 1).setFill()
        background.fill()

        let strap = NSBezierPath(roundedRect: NSRect(x: 100, y: 455, width: 824, height: 132), xRadius: 66, yRadius: 66)
        NSColor(calibratedRed: 0.24, green: 0.31, blue: 0.31, alpha: 1).setFill()
        strap.fill()

        let buckleLeft = NSBezierPath(roundedRect: NSRect(x: 90, y: 440, width: 142, height: 162), xRadius: 34, yRadius: 34)
        let buckleRight = NSBezierPath(roundedRect: NSRect(x: 792, y: 440, width: 142, height: 162), xRadius: 34, yRadius: 34)
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
        buckleLeft.fill()
        buckleRight.fill()

        let pouch = NSBezierPath(roundedRect: NSRect(x: 190, y: 268, width: 644, height: 474), xRadius: 138, yRadius: 138)
        NSColor(calibratedRed: 0.91, green: 0.35, blue: 0.16, alpha: 1).setFill()
        pouch.fill()

        let lowerShade = NSBezierPath(roundedRect: NSRect(x: 215, y: 288, width: 594, height: 216), xRadius: 94, yRadius: 94)
        NSColor(calibratedRed: 0.71, green: 0.21, blue: 0.11, alpha: 0.36).setFill()
        lowerShade.fill()

        let zipperTrack = NSBezierPath(roundedRect: NSRect(x: 300, y: 625, width: 424, height: 28), xRadius: 14, yRadius: 14)
        NSColor(calibratedWhite: 0.97, alpha: 0.88).setFill()
        zipperTrack.fill()

        for index in 0..<18 {
            let tooth = NSBezierPath(roundedRect: NSRect(x: 310 + CGFloat(index * 22), y: 610, width: 12, height: 55), xRadius: 4, yRadius: 4)
            NSColor(calibratedWhite: index.isMultiple(of: 2) ? 0.96 : 0.82, alpha: 1).setFill()
            tooth.fill()
        }

        let pull = NSBezierPath(roundedRect: NSRect(x: 668, y: 582, width: 74, height: 92), xRadius: 24, yRadius: 24)
        NSColor(calibratedRed: 0.97, green: 0.78, blue: 0.25, alpha: 1).setFill()
        pull.fill()
        let pullHole = NSBezierPath(ovalIn: NSRect(x: 690, y: 605, width: 30, height: 38))
        NSColor(calibratedRed: 0.50, green: 0.18, blue: 0.10, alpha: 1).setFill()
        pullHole.fill()

        let pocket = NSBezierPath(roundedRect: NSRect(x: 328, y: 356, width: 368, height: 128), xRadius: 55, yRadius: 55)
        NSColor(calibratedWhite: 0.10, alpha: 0.22).setFill()
        pocket.fill()
        let stitch = NSBezierPath()
        stitch.move(to: NSPoint(x: 370, y: 430))
        stitch.line(to: NSPoint(x: 654, y: 430))
        stitch.lineWidth = 10
        NSColor(calibratedWhite: 1, alpha: 0.60).setStroke()
        stitch.stroke()

        context.flushGraphics()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
    }
}
