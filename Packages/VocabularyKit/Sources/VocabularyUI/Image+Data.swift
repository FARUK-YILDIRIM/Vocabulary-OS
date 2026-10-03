import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Image {
    /// An image from encoded data (JPEG, PNG, HEIC) on iOS and macOS, or `nil` if it can't be decoded.
    public init?(imageData: Data) {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData) else { return nil }
        self.init(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: imageData) else { return nil }
        self.init(nsImage: image)
        #endif
    }
}
