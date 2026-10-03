import Foundation

/// Why a photo could not be captured.
public enum CaptureError: Error, Equatable, Sendable, LocalizedError {
    /// The data is not an image the system can read.
    case unreadableImage
    /// Vision could not analyze the image.
    case recognitionFailed

    public var errorDescription: String? {
        switch self {
        case .unreadableImage:
            String(localized: "This file isn't an image Vocabulary-OS can read.", bundle: .module)
        case .recognitionFailed:
            String(localized: "The photo couldn't be analyzed. Try again, or try a sharper photo.", bundle: .module)
        }
    }
}
