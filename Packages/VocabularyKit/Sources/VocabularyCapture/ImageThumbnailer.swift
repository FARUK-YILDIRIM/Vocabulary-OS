import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The downscaled photos Vocabulary-OS stores instead of originals (ADR-005).
public enum ImageThumbnailer {
    /// The longest edge of a stored photo, in pixels.
    public static let maximumPixelSize = 1024
    public static let compressionQuality = 0.7

    /// An upright JPEG no larger than `maximumPixelSize` on its long edge, or `nil` if the data isn't
    /// an image. Only pixels are copied, so metadata such as the location is left behind.
    public static func thumbnail(of imageData: Data) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
