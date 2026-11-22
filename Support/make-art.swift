// Draws the app icon and the background of the install window from
// Support/art/pocket-sky.png. Run from the repository root after changing
// that picture or the layout below:
//
//     swift Support/make-art.swift
//
// The results are committed, so a release build does not run this.

import AppKit
import SwiftUI

let source = "Support/art/pocket-sky.png"
let iconSet = "Sources/Assets.xcassets/AppIcon.appiconset"
let dmgFolder = "Support/dmg"

guard let picture = NSImage(contentsOfFile: source)?
    .cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    fatalError("cannot read \(source)")
}

func canvas(_ width: Int, _ height: Int, _ draw: (CGContext) -> Void) -> CGImage {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("no bitmap context") }
    context.interpolationQuality = .high
    draw(context)
    return context.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    guard let file = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("cannot write \(path)")
    }
    CGImageDestinationAddImage(file, image, nil)
    guard CGImageDestinationFinalize(file) else { fatalError("cannot write \(path)") }
    print(path)
}

// MARK: - App icon

// Apple's macOS icon grid: an 824 pt rounded square on a 1024 pt canvas, with
// a soft shadow under it.
let iconMaster = canvas(1024, 1024) { context in
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: plate).cgPath

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10), blur: 20,
        color: CGColor(gray: 0, alpha: 0.3)
    )
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // The square of the picture around the word "pocket" (pixels, from the
    // top left of the 2576 x 1449 source).
    let crop = CGRect(x: 716, y: 150, width: 1150, height: 1150)
    context.addPath(shape)
    context.clip()
    context.draw(picture.cropping(to: crop)!, in: plate)
}

var iconEntries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let scaled = canvas(pixels, pixels) { context in
            context.draw(iconMaster, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        }
        write(scaled, to: "\(iconSet)/\(name)")
        iconEntries.append(
            """
                { "idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": "\(name)" }
            """
        )
    }
}
let contents = """
{
  "images": [
\(iconEntries.joined(separator: ",\n"))
  ],
  "info": { "author": "xcode", "version": 1 }
}

"""
try! contents.write(toFile: "\(iconSet)/Contents.json", atomically: true, encoding: .utf8)
try! """
{
  "info": { "author": "xcode", "version": 1 }
}

""".write(toFile: "Sources/Assets.xcassets/Contents.json", atomically: true, encoding: .utf8)

// MARK: - Install window

// Size of the install window's content in points. KEEP IN SYNC with
// Support/dmg/settings.py, which places the two icons at y = 200 and
// x = 170 and 490.
let windowSize = CGSize(width: 660, height: 420)

func installBackground(scale: CGFloat) -> CGImage {
    canvas(Int(windowSize.width * scale), Int(windowSize.height * scale)) { context in
        context.scaleBy(x: scale, y: scale)
        let bounds = CGRect(origin: .zero, size: windowSize)

        // The left of the picture has no lettering; stretched sideways it is
        // still the same soft sky. The crop stops above the brightest clouds,
        // so Finder's white labels (dark mode) stay readable under the icons.
        let sky = picture.cropping(to: CGRect(x: 0, y: 0, width: 820, height: 1120))!
        context.draw(sky, in: bounds)

        // Flip to a top-left origin: the layout numbers below then match the
        // ones Finder uses.
        context.translateBy(x: 0, y: windowSize.height)
        context.scaleBy(x: 1, y: -1)

        let white = CGColor(gray: 1, alpha: 1)
        context.setShadow(offset: .zero, blur: 14, color: CGColor(gray: 1, alpha: 0.9))

        // The arrow between the two icons.
        let middle: CGFloat = 200
        context.setStrokeColor(white)
        context.setLineWidth(7)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: 288, y: middle))
        context.addLine(to: CGPoint(x: 372, y: middle))
        context.move(to: CGPoint(x: 348, y: middle - 24))
        context.addLine(to: CGPoint(x: 372, y: middle))
        context.addLine(to: CGPoint(x: 348, y: middle + 24))
        context.strokePath()

        // The one line of instruction, above the icons.
        let text = NSAttributedString(
            string: "drag pocket to applications",
            attributes: [
                .font: NSFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: NSColor.white,
                .kern: -0.2,
            ]
        )
        let line = CTLineCreateWithAttributedString(text)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        // Core Text draws upwards, so undo the flip around the baseline.
        let baseline: CGFloat = 72
        context.saveGState()
        context.translateBy(x: (windowSize.width - width) / 2, y: baseline)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

write(installBackground(scale: 1), to: "\(dmgFolder)/background.png")
write(installBackground(scale: 2), to: "\(dmgFolder)/background@2x.png")
