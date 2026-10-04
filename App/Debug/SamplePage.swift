#if DEBUG
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A generated book page for UI tests and the macOS self-test (`-vos-sample-page YES`): the Simulator
/// has no camera and an empty photo library.
enum SamplePage {
    static let text = """
        Ich muss heute noch zur Bank, um Geld abzuheben. Danach treffe ich meine Freundin im Park, wo wir auf einer alten Bank sitzen und reden.

        The old man ran the family company for ten years. Every morning he walked to the office, even when it was raining cats and dogs.
        """

    /// Black Georgia text on white, as JPEG data like a photo would arrive.
    static func jpegData(width: Int = 1200, height: Int = 900) -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Georgia" as CFString, 34, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ]
        let framesetter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let path = CGPath(rect: CGRect(x: 80, y: 80, width: width - 160, height: height - 160), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil), context)

        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
#endif
