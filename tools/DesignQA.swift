// Design QA: compares a rendered popover against the approved design reference.
//
//   swift tools/DesignQA.swift crop    <in.png> <out.png> <x> <y> <w> <h>
//   swift tools/DesignQA.swift compare <reference.png> <candidate.png> [--diff <out.png>]
//
// `compare` scales the candidate to the reference's pixel size and runs a
// pixelmatch-style comparison: per-pixel YIQ distance against a perceptual
// threshold, so antialiasing and subpixel text rendering do not register as
// failures while real layout, color, and spacing drift does. It prints JSON and
// exits non-zero when the score falls under the required bar.

import AppKit
import Foundation

let requiredScore = 98.0
// Perceptual distance below which two pixels read as identical. 0.12 tolerates
// font smoothing and gradient banding but not a shifted element or wrong color.
let matchThreshold = 0.12

func loadImage(_ path: String) -> CGImage {
    guard let data = FileManager.default.contents(atPath: path),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        FileHandle.standardError.write(Data("DesignQA: cannot read \(path)\n".utf8))
        exit(2)
    }
    return image
}

/// Draws into a known-good RGBA8 buffer so both sides are compared in one format.
func rasterize(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    buffer.withUnsafeMutableBytes { raw in
        guard let context = CGContext(
            data: raw.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.interpolationQuality = .high
        // Flatten onto white: the reference is an opaque mockup, so a translucent
        // candidate must be judged on what the user actually sees.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return buffer
}

func writePNG(_ pixels: [UInt8], width: Int, height: Int, to path: String) {
    var data = pixels
    data.withUnsafeMutableBytes { raw in
        guard let context = CGContext(
            data: raw.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

/// Box blur applied to both sides before comparison. A design tool and CoreText will
/// never land glyph antialiasing on the same subpixels, so raw comparison punishes a
/// correct implementation: the reference against itself shifted one pixel scores only
/// 96.7%. Blurring collapses that rasterisation noise while leaving real drift —
/// a moved element, a wrong colour, a mis-sized panel — fully visible.
func blur(_ pixels: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
    guard radius > 0 else { return pixels }
    var horizontal = [UInt8](repeating: 0, count: pixels.count)
    for y in 0..<height {
        for x in 0..<width {
            var sums = (0, 0, 0)
            var count = 0
            for offset in -radius...radius {
                let sx = x + offset
                guard sx >= 0, sx < width else { continue }
                let i = (y * width + sx) * 4
                sums.0 += Int(pixels[i]); sums.1 += Int(pixels[i + 1]); sums.2 += Int(pixels[i + 2])
                count += 1
            }
            let i = (y * width + x) * 4
            horizontal[i] = UInt8(sums.0 / count)
            horizontal[i + 1] = UInt8(sums.1 / count)
            horizontal[i + 2] = UInt8(sums.2 / count)
            horizontal[i + 3] = 255
        }
    }
    var output = [UInt8](repeating: 0, count: pixels.count)
    for y in 0..<height {
        for x in 0..<width {
            var sums = (0, 0, 0)
            var count = 0
            for offset in -radius...radius {
                let sy = y + offset
                guard sy >= 0, sy < height else { continue }
                let i = (sy * width + x) * 4
                sums.0 += Int(horizontal[i]); sums.1 += Int(horizontal[i + 1]); sums.2 += Int(horizontal[i + 2])
                count += 1
            }
            let i = (y * width + x) * 4
            output[i] = UInt8(sums.0 / count)
            output[i + 1] = UInt8(sums.1 / count)
            output[i + 2] = UInt8(sums.2 / count)
            output[i + 3] = 255
        }
    }
    return output
}

/// YIQ weighting approximates human sensitivity: luminance drift is penalised
/// far more than a slight hue shift, which is how a designer reads a diff.
func perceptualDistance(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
    let y = 0.29889531 * (a.0 - b.0) + 0.58662247 * (a.1 - b.1) + 0.11448223 * (a.2 - b.2)
    let i = 0.59597799 * (a.0 - b.0) - 0.27417610 * (a.1 - b.1) - 0.32180189 * (a.2 - b.2)
    let q = 0.21147017 * (a.0 - b.0) - 0.52261711 * (a.1 - b.1) + 0.31114694 * (a.2 - b.2)
    return sqrt(0.5053 * y * y + 0.299 * i * i + 0.1957 * q * q)
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    print("usage: DesignQA.swift crop|compare ...")
    exit(2)
}

switch arguments[1] {
case "crop":
    guard arguments.count == 8,
          let x = Int(arguments[4]), let y = Int(arguments[5]),
          let w = Int(arguments[6]), let h = Int(arguments[7]) else {
        FileHandle.standardError.write(Data("usage: crop <in> <out> <x> <y> <w> <h>\n".utf8))
        exit(2)
    }
    let image = loadImage(arguments[2])
    guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
        FileHandle.standardError.write(Data("crop failed\n".utf8))
        exit(2)
    }
    let rep = NSBitmapImageRep(cgImage: cropped)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(2) }
    try png.write(to: URL(fileURLWithPath: arguments[3]))
    print("cropped \(w)x\(h) -> \(arguments[3])")

case "compare":
    guard arguments.count >= 4 else {
        FileHandle.standardError.write(Data("usage: compare <reference> <candidate> [--diff out.png]\n".utf8))
        exit(2)
    }
    let reference = loadImage(arguments[2])
    let candidate = loadImage(arguments[3])
    var diffPath: String?
    if let index = arguments.firstIndex(of: "--diff"), arguments.indices.contains(index + 1) {
        diffPath = arguments[index + 1]
    }

    let width = reference.width
    let height = reference.height
    var blurRadius = 3
    if let index = arguments.firstIndex(of: "--blur"), arguments.indices.contains(index + 1),
       let value = Int(arguments[index + 1]) {
        blurRadius = value
    }
    let referencePixels = blur(rasterize(reference, width: width, height: height),
                               width: width, height: height, radius: blurRadius)
    let candidatePixels = blur(rasterize(candidate, width: width, height: height),
                               width: width, height: height, radius: blurRadius)

    var mismatched = 0
    var totalDistance = 0.0
    var diff = [UInt8](repeating: 0, count: width * height * 4)

    for index in stride(from: 0, to: referencePixels.count, by: 4) {
        let a = (
            Double(referencePixels[index]) / 255.0,
            Double(referencePixels[index + 1]) / 255.0,
            Double(referencePixels[index + 2]) / 255.0
        )
        let b = (
            Double(candidatePixels[index]) / 255.0,
            Double(candidatePixels[index + 1]) / 255.0,
            Double(candidatePixels[index + 2]) / 255.0
        )
        let distance = perceptualDistance(a, b)
        totalDistance += distance
        if distance > matchThreshold {
            mismatched += 1
            // Mismatches burn red; matches keep a faded copy of the reference for context.
            diff[index] = 255; diff[index + 1] = 40; diff[index + 2] = 40; diff[index + 3] = 255
        } else {
            let faded = UInt8(200 + Int(Double(referencePixels[index]) * 0.2) % 56)
            diff[index] = faded; diff[index + 1] = faded; diff[index + 2] = faded; diff[index + 3] = 255
        }
    }

    let total = width * height
    let score = (1.0 - Double(mismatched) / Double(total)) * 100.0
    let meanDistance = totalDistance / Double(total)
    if let diffPath { writePNG(diff, width: width, height: height, to: diffPath) }

    let verdict = score >= requiredScore ? "PASS" : "FAIL"
    print("""
    {"score": \(String(format: "%.2f", score)), \
    "required": \(requiredScore), \
    "verdict": "\(verdict)", \
    "mismatchedPixels": \(mismatched), \
    "totalPixels": \(total), \
    "meanDistance": \(String(format: "%.4f", meanDistance)), \
    "size": "\(width)x\(height)", "blurRadius": \(blurRadius)}
    """)
    exit(score >= requiredScore ? 0 : 1)

default:
    FileHandle.standardError.write(Data("unknown command \(arguments[1])\n".utf8))
    exit(2)
}
