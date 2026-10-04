// Draws the app icon into App/Resources/Assets.xcassets/AppIcon.appiconset: a speech bubble whose
// lines of text have one word highlighted, the word picked from its sentence, and a sparkle for the
// AI that explains it. Drawn from shapes, since SF Symbols may not be used in app icons.
// Usage: swift scripts/tools/make-app-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

/// The icon at `size` pixels, drawn on a 1024-point grid with y pointing down.
func icon(size: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(size) / 1024
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: scale, y: -scale)

    // Background: the app's accent blue, deeper at the top.
    let background = CGGradient(
        colorsSpace: space,
        colors: [color(0.15, 0.29, 0.52), color(0.29, 0.55, 0.83)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(background, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])

    // The bubble, with a tail at its lower left and a soft shadow under both. They are filled one
    // after the other in one layer: as one path, their overlap would be left empty.
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: 282, y: 680))
    tail.addLine(to: CGPoint(x: 224, y: 836))
    tail.addLine(to: CGPoint(x: 432, y: 694))
    tail.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 18), blur: 36, color: color(0.03, 0.08, 0.2, 0.35))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setFillColor(color(1, 1, 1))
    context.addPath(CGPath(roundedRect: CGRect(x: 172, y: 262, width: 680, height: 452), cornerWidth: 116, cornerHeight: 116, transform: nil))
    context.fillPath()
    context.addPath(tail)
    context.fillPath()
    context.endTransparencyLayer()
    context.restoreGState()

    // Lines of text; one word on the middle line is highlighted.
    func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ fill: CGColor) {
        context.setFillColor(fill)
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: 58), cornerWidth: 29, cornerHeight: 29, transform: nil))
        context.fillPath()
    }
    let text = color(0.78, 0.84, 0.93)
    bar(256, 350, 512, text)
    bar(256, 446, 150, text)
    bar(430, 446, 216, color(1.0, 0.76, 0.2))
    bar(670, 446, 98, text)
    bar(256, 542, 340, text)

    // A four-pointed sparkle above the bubble's upper right corner.
    let center = CGPoint(x: 848, y: 166), radius: CGFloat = 70, pinch: CGFloat = 13
    let sparkle = CGMutablePath()
    sparkle.move(to: CGPoint(x: center.x, y: center.y - radius))
    sparkle.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + pinch, y: center.y - pinch))
    sparkle.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x + pinch, y: center.y + pinch))
    sparkle.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - pinch, y: center.y + pinch))
    sparkle.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x - pinch, y: center.y - pinch))
    context.setFillColor(color(1, 1, 1))
    context.addPath(sparkle)
    context.fillPath()

    return context.makeImage()!
}

func write(_ image: CGImage, to name: String) {
    let url = output.appending(path: name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(name)") }
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
write(icon(size: 1024), to: "AppIcon-1024.png")
images.append(["filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"])
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "AppIcon-mac-\(points)@\(scale)x.png"
        write(icon(size: points * scale), to: name)
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: output.appending(path: "Contents.json"))
print("Wrote \(images.count) images to \(output.path)")
