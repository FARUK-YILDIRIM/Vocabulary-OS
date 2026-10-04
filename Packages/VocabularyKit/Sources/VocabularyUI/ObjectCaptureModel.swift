import CoreGraphics
import Foundation
import Observation
import VocabularyAI
import VocabularyCapture
import VocabularyCore
import VocabularyData

/// Object capture (SPEC C6, ADR-005): a photo is classified on device, the learner confirms or types
/// what it shows, the AI names it in a learning language, and the word is saved with the photo.
@Observable
public final class ObjectCaptureModel {
    public enum Phase: Equatable {
        /// No photo yet.
        case empty
        case classifying
        /// The learner confirms what the object is and picks the language.
        case choosing
        case naming
        case named
        case saved
        case failed(CaptureError)
    }

    public private(set) var phase = Phase.empty
    /// The photo, upright and downscaled for display.
    public private(set) var displayImage: CGImage?
    /// What Vision thinks the photo shows, most specific first.
    public private(set) var labels: [ObjectLabel] = []
    /// What the object is: a label's name or what the learner typed, in any language.
    public var label = "" {
        didSet {
            if label != oldValue { discardName() }
        }
    }
    /// The learning language to name the object in.
    public var language: LanguageCode? {
        didSet {
            if language != oldValue { discardName() }
        }
    }
    public private(set) var insight: WordInsight?
    public private(set) var namingError: AIError?
    /// Set when the word is already saved, so the learner can decide before saving it twice.
    public private(set) var duplicateTranslation: String?
    public private(set) var saveErrorMessage: String?
    /// Whether the word keeps a small copy of the photo (ADR-005).
    public var savesPhoto = true

    private var imageData: Data?
    private var thumbnail: Data?
    private var loadID = UUID()
    private var namingTask: Task<Void, Never>?
    private let settings: SettingsStore
    private let classify: (Data) async throws(CaptureError) -> [ObjectLabel]
    private let destination: (_ photo: Data?) -> any CaptureDestination
    private let makeInsightService: () -> InsightService

    /// - Parameters:
    ///   - classify: labels for the photo; Vision's classifier unless a test replaces it.
    ///   - destination: where the word goes, given the photo to save with it, if any.
    public init(
        settings: SettingsStore,
        classify: @escaping (Data) async throws(CaptureError) -> [ObjectLabel] = { data throws(CaptureError) in
            try await ObjectClassifier().labels(for: data)
        },
        destination: @escaping (_ photo: Data?) -> any CaptureDestination,
        insightService: @escaping () -> InsightService
    ) {
        self.settings = settings
        self.classify = classify
        self.destination = destination
        self.makeInsightService = insightService
    }

    public var languageChoices: [LanguageCode] {
        settings.profile?.learning ?? []
    }

    public var canName: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && language != nil
            && settings.profile != nil && phase != .naming && phase != .classifying
    }

    // MARK: Photo

    /// Shows the photo and classifies it. A newer photo replaces one still being classified, and a
    /// cancelled load leaves the capture empty. When classification fails, the learner types what
    /// the object is: the classifier needs hardware some devices and the iOS Simulator lack.
    public func load(_ data: Data) async {
        let id = UUID()
        loadID = id
        clear()
        imageData = data
        displayImage = ImageThumbnailer.image(of: data, maximumPixelSize: PageCaptureModel.displayPixelSize)
        guard displayImage != nil else {
            phase = .failed(.unreadableImage)
            return
        }
        phase = .classifying
        var labels: [ObjectLabel] = []
        do throws(CaptureError) {
            labels = try await classify(data)
        } catch {
            guard loadID == id else { return }
            guard error != .cancelled, !Task.isCancelled else { return reset() }
            guard error == .recognitionFailed else {
                phase = .failed(error)
                return
            }
        }
        guard loadID == id else { return }
        guard !Task.isCancelled else { return reset() }
        self.labels = labels
        label = labels.first?.name ?? ""
        language = language ?? languageChoices.first
        phase = .choosing
    }

    // MARK: Naming

    public func name() {
        guard canName, let language, let native = settings.profile?.native else { return }
        let request = ObjectNamingRequest(
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language,
            nativeLanguage: native
        )
        let service = ObjectNamingService(makeInsightService())
        namingTask?.cancel()
        namingError = nil
        phase = .naming
        namingTask = Task { [weak self] in
            do throws(AIError) {
                let insight = try await service.name(request)
                guard !Task.isCancelled else { return }
                self?.finish(with: insight)
            } catch {
                guard !Task.isCancelled else { return }
                self?.namingError = error
                self?.phase = .choosing
            }
        }
    }

    /// Waits for the current naming; for tests and UI that needs to sequence work.
    public func waitForName() async {
        await namingTask?.value
    }

    private func finish(with insight: WordInsight) {
        self.insight = insight
        duplicateTranslation = destination(nil).savedTranslation(lemma: insight.lemma, language: insight.language)
        phase = .named
    }

    private func discardName() {
        namingTask?.cancel()
        insight = nil
        namingError = nil
        duplicateTranslation = nil
        saveErrorMessage = nil
        if phase == .named || phase == .naming || phase == .saved {
            phase = .choosing
        }
    }

    // MARK: Saving

    public func save() {
        guard let insight else { return }
        do {
            try destination(savesPhoto ? photoThumbnail() : nil).save(insight, captureSource: .object)
            saveErrorMessage = nil
            phase = .saved
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    /// Back to choosing a photo.
    public func reset() {
        loadID = UUID()
        clear()
    }

    private func clear() {
        namingTask?.cancel()
        phase = .empty
        imageData = nil
        thumbnail = nil
        displayImage = nil
        labels = []
        label = ""
        insight = nil
        namingError = nil
        duplicateTranslation = nil
        saveErrorMessage = nil
    }

    private func photoThumbnail() -> Data? {
        if thumbnail == nil, let imageData {
            thumbnail = ImageThumbnailer.thumbnail(of: imageData)
        }
        return thumbnail
    }
}
