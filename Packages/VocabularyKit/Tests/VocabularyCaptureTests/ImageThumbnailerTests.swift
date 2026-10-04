import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import VocabularyCapture

@Suite struct ImageThumbnailerTests {
    private func size(of data: Data) throws -> (width: Int, height: Int, type: String?) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0, CGImageSourceGetType(source) as String?)
    }

    @Test func limitsTheLongEdgeTo1024PixelsAsJPEG() throws {
        let photo = TestImages.jpeg(TestImages.blank(width: 4032, height: 3024))
        let thumbnail = try #require(ImageThumbnailer.thumbnail(of: photo))
        let result = try size(of: thumbnail)

        #expect(result.width == 1024)
        #expect(result.height == 768)
        #expect(result.type == UTType.jpeg.identifier)
    }

    @Test func turnsSidewaysPhotosUpright() throws {
        let sideways = TestImages.jpeg(TestImages.blank(width: 3024, height: 4032), exifOrientation: 6)
        let result = try size(of: try #require(ImageThumbnailer.thumbnail(of: sideways)))

        #expect(result.width == 1024)
        #expect(result.height == 768)
    }

    @Test func neverEnlargesSmallImages() throws {
        let small = TestImages.jpeg(TestImages.blank(width: 640, height: 480))
        let result = try size(of: try #require(ImageThumbnailer.thumbnail(of: small)))

        #expect(result.width == 640)
        #expect(result.height == 480)
    }

    @Test func makesUprightDisplayImagesOfAnySize() throws {
        let sideways = TestImages.jpeg(TestImages.blank(width: 3024, height: 4032), exifOrientation: 6)
        let image = try #require(ImageThumbnailer.image(of: sideways, maximumPixelSize: 2048))

        #expect(image.width == 2048)
        #expect(image.height == 1536)
    }

    @Test func rejectsDataThatIsNotAnImage() {
        #expect(ImageThumbnailer.thumbnail(of: Data("nope".utf8)) == nil)
    }
}
