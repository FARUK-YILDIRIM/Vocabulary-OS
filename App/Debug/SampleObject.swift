#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A stand-in photo of a cup for UI tests and the macOS self-test (`-vos-sample-object YES`): an SF
/// Symbol the system draws at run time, which Vision classifies as a cup.
enum SampleObject {
    static func jpegData(size: Int = 600) -> Data {
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        draw(symbol: "cup.and.saucer.fill", in: context, size: CGFloat(size))

        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private static func draw(symbol: String, in context: CGContext, size: CGFloat) {
        #if canImport(UIKit)
        let configuration = UIImage.SymbolConfiguration(pointSize: size * 0.6)
        guard let image = UIImage(systemName: symbol, withConfiguration: configuration)?
            .withTintColor(.brown, renderingMode: .alwaysOriginal) else { return }
        UIGraphicsPushContext(context)
        // UIKit draws with the origin at the top left; the bitmap context starts at the bottom left.
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: 1, y: -1)
        image.draw(in: CGRect(x: (size - image.size.width) / 2, y: (size - image.size.height) / 2, width: image.size.width, height: image.size.height))
        UIGraphicsPopContext()
        #else
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.6, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.brown]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: (size - image.size.width) / 2, y: (size - image.size.height) / 2, width: image.size.width, height: image.size.height))
        NSGraphicsContext.current = nil
        #endif
    }
}
#endif
