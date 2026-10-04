#if canImport(AppKit)
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A stand-in photo of an object for object-capture tests: an SF Symbol drawn large at test time.
enum ObjectImages {
    /// JPEG data of the symbol; `cup.and.saucer.fill` is classified as a cup.
    static func jpeg(symbol name: String = "cup.and.saucer.fill", size: Int = 600) -> Data {
        let configuration = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.6, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.brown]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(
            x: (CGFloat(size) - image.size.width) / 2, y: (CGFloat(size) - image.size.height) / 2,
            width: image.size.width, height: image.size.height
        ))
        NSGraphicsContext.current = nil

        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
#endif
