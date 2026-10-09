// Centers a captured window on an opaque canvas of an App Store screenshot size, scaled to fit with a
// margin. The App Store doesn't accept screenshots with transparency, which window captures have in
// their rounded corners.
// Usage: swift scripts/tools/compose-screenshot.swift window.png out.png 1440 900
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 5, let width = Int(arguments[3]), let height = Int(arguments[4]),
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let window = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    FileHandle.standardError.write(Data("usage: compose-screenshot.swift window.png out.png width height\n".utf8))
    exit(1)
}

let margin = Double(min(width, height)) * 0.04
let scale = min((Double(width) - 2 * margin) / Double(window.width), (Double(height) - 2 * margin) / Double(window.height))
let size = CGSize(width: Double(window.width) * scale, height: Double(window.height) * scale)
let origin = CGPoint(x: (Double(width) - size.width) / 2, y: (Double(height) - size.height) / 2)

guard let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { exit(1) }
// The light grouped background the app's forms use.
context.setFillColor(CGColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
context.interpolationQuality = .high
context.draw(window, in: CGRect(origin: origin, size: size))

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
