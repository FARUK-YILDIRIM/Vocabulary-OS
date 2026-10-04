import Foundation
import ImageIO
import os
import Vision
import VocabularyCore

/// Recognizes the text on a photographed page with Vision's document recognition (ADR-005).
///
/// `RecognizeDocumentsRequest` returns paragraphs whose transcripts already join wrapped lines, and
/// the words of each paragraph with their boxes, which is what tapping a word on a page needs.
public struct PageTextRecognizer: Sendable {
    private static let logger = Logger(subsystem: VocabularyCore.logSubsystem, category: VocabularyCapture.logCategory)

    public init() {}

    /// Recognizes the page in image file data (JPEG, HEIC, PNG …). Vision applies the file's
    /// orientation, so the word boxes match the photo as it is displayed.
    /// - Parameter languages: the learner's languages; those Vision supports guide recognition.
    public func recognize(_ imageData: Data, languages: [LanguageCode]) async throws(CaptureError) -> PageText {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw .unreadableImage
        }
        var request = RecognizeDocumentsRequest()
        let supported = Self.supported(languages, by: request.supportedRecognitionLanguages)
        if !supported.isEmpty {
            request.textRecognitionOptions.recognitionLanguages = supported
        }
        let observations: [DocumentObservation]
        do {
            observations = try await request.perform(on: imageData)
        } catch {
            if Task.isCancelled {
                throw .cancelled
            }
            Self.logger.error("Page recognition failed: \(error.localizedDescription, privacy: .public)")
            throw .recognitionFailed
        }
        let paragraphs = observations.flatMap(\.document.paragraphs).map { paragraph in
            PageText.RecognizedParagraph(
                transcript: paragraph.transcript,
                words: (paragraph.words ?? []).compactMap { word in
                    guard let text = word.topCandidates(1).first?.string else { return nil }
                    // Vision's normalized boxes start at the bottom left; overlays draw from the top left.
                    return PageText.RecognizedWord(text: text, box: word.boundingBox.verticallyFlipped().cgRect)
                }
            )
        }
        return PageText(paragraphs)
    }

    /// The learner's languages in the form Vision lists them, skipping those it doesn't support.
    static func supported(_ languages: [LanguageCode], by available: [Locale.Language]) -> [Locale.Language] {
        languages.compactMap { code in
            let wanted = Locale.Language(identifier: code.rawValue)
            return available.first { $0.maximalIdentifier == wanted.maximalIdentifier }
                ?? available.first { $0.languageCode == wanted.languageCode && $0.script == wanted.script }
                ?? available.first { $0.languageCode == wanted.languageCode }
        }
    }
}
