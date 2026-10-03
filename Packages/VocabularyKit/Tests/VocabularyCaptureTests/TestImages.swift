import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Generated images for capture tests, drawn with Core Text so they look like a printed page.
enum TestImages {
    static let germanAndEnglishPage = """
        Ich muss heute noch zur Bank, um Geld abzuheben. Danach treffe ich meine Freundin im Park, wo wir auf einer alten Bank sitzen und reden.

        The old man ran the family company for ten years. Every morning he walked to the office, even when it was raining cats and dogs.
        """

    /// Black Georgia text on white, laid out in a frame with margins so sentences wrap across lines.
    static func page(_ text: String, size: CGSize = CGSize(width: 1200, height: 900), fontSize: CGFloat = 34) -> CGImage {
        let context = blankContext(width: Int(size.width), height: Int(size.height))
        let font = CTFontCreateWithName("Georgia" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ]
        let framesetter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let path = CGPath(rect: CGRect(x: 80, y: 80, width: size.width - 160, height: size.height - 160), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil), context)
        return context.makeImage()!
    }

    /// A plain image of the given size, for thumbnail tests.
    static func blank(width: Int, height: Int) -> CGImage {
        blankContext(width: width, height: height).makeImage()!
    }

    /// The image turned a quarter turn clockwise, as a camera held sideways stores its pixels.
    static func rotatedClockwise(_ image: CGImage) -> CGImage {
        let context = blankContext(width: image.height, height: image.width)
        context.translateBy(x: 0, y: CGFloat(image.width))
        context.rotate(by: -.pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()!
    }

    /// JPEG data, optionally tagged with an EXIF orientation (1 = up, 8 = rotate left to display).
    static func jpeg(_ image: CGImage, exifOrientation: Int? = nil) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let exifOrientation {
            properties[kCGImagePropertyOrientation] = exifOrientation
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private static func blankContext(width: Int, height: Int) -> CGContext {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }
}
