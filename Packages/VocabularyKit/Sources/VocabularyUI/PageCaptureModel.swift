import CoreGraphics
import Foundation
import Observation
import VocabularyAI
import VocabularyCapture
import VocabularyCore
import VocabularyData

/// Page capture (SPEC C6, ADR-005): a photo of a page becomes tappable words, and a tapped word opens
/// the capture flow with the sentence it is in.
@Observable
public final class PageCaptureModel {
    public enum Phase: Equatable {
        /// No photo yet.
        case empty
        case recognizing
        case recognized
        case failed(CaptureError)
    }

    /// The long edge of the photo as displayed. Word boxes are normalized, so any size works.
    static let displayPixelSize = 2048

    public private(set) var phase = Phase.empty
    /// The photo, upright and downscaled for display.
    public private(set) var displayImage: CGImage?
    public private(set) var page: PageText?
    /// The word the learner tapped last, highlighted on the photo.
    public private(set) var tappedWord: PageText.Word?
    /// Whether words captured from this page keep a small copy of the photo (ADR-005).
    public var savesPhoto = true
    /// The capture flow for the tapped word, while it is open.
    public var capture: CaptureModel?

    private var imageData: Data?
    private var thumbnail: Data?
    private var loadID = UUID()
    private let settings: SettingsStore
    private let destination: (_ photo: Data?) -> any CaptureDestination
    private let makeInsightService: () -> InsightService
    private let recognizer = PageTextRecognizer()

    /// - Parameter destination: where a capture goes, given the photo to save with it, if any.
    public init(
        settings: SettingsStore,
        destination: @escaping (_ photo: Data?) -> any CaptureDestination,
        insightService: @escaping () -> InsightService
    ) {
        self.settings = settings
        self.destination = destination
        self.makeInsightService = insightService
    }

    /// Shows the photo and finds its words. A newer photo replaces one still being recognized, and a
    /// cancelled load leaves the page empty.
    public func load(_ data: Data) async {
        let id = UUID()
        loadID = id
        imageData = data
        thumbnail = nil
        page = nil
        tappedWord = nil
        capture = nil
        displayImage = ImageThumbnailer.image(of: data, maximumPixelSize: Self.displayPixelSize)
        guard displayImage != nil else {
            phase = .failed(.unreadableImage)
            return
        }
        phase = .recognizing
        let languages = settings.profile.map { $0.learning + [$0.native] } ?? []
        do throws(CaptureError) {
            let page = try await recognizer.recognize(data, languages: languages)
            guard loadID == id else { return }
            guard !Task.isCancelled else { return reset() }
            self.page = page
            phase = .recognized
        } catch {
            guard loadID == id else { return }
            guard error != .cancelled, !Task.isCancelled else { return reset() }
            phase = .failed(error)
        }
    }

    /// Opens the capture flow for a word on the page, with its sentence as the context.
    public func tap(_ word: PageText.Word) {
        guard let page else { return }
        tappedWord = word
        let model = CaptureModel(
            text: page.sentence(containing: word) ?? word.text,
            captureSource: .page,
            settings: settings,
            destination: destination(savesPhoto ? photoThumbnail() : nil),
            insightService: makeInsightService
        )
        model.selectFirst(matching: word.text)
        capture = model
    }

    /// Back to choosing a photo.
    public func reset() {
        loadID = UUID()
        phase = .empty
        imageData = nil
        thumbnail = nil
        displayImage = nil
        page = nil
        tappedWord = nil
        capture = nil
    }

    private func photoThumbnail() -> Data? {
        if thumbnail == nil, let imageData {
            thumbnail = ImageThumbnailer.thumbnail(of: imageData)
        }
        return thumbnail
    }
}
