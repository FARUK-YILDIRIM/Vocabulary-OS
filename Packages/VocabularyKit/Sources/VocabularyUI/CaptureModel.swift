import Foundation
import Observation
import VocabularyAI
import VocabularyCore
import VocabularyData

/// Where a finished capture goes: the library in the app, the inbox in the Share extension.
public protocol CaptureDestination {
    /// The translation of a word already saved with this lemma and language, to warn about duplicates.
    func savedTranslation(lemma: String, language: LanguageCode) -> String?
    func save(_ insight: WordInsight, captureSource: CaptureSource) throws
}

/// The capture flow: text → selected term → language → insight → save (SPEC C3, C5).
@Observable
public final class CaptureModel {
    public enum Phase: Equatable {
        /// No term selected yet.
        case idle
        case ready
        case explaining
        case explained
        case failed(AIError)
        case saved
    }

    public var text: String = "" {
        didSet {
            if text != oldValue { textChanged() }
        }
    }

    public private(set) var tokens = TokenizedText("")
    public private(set) var selection: ClosedRange<Int>?
    public private(set) var term: String?
    public private(set) var sentence: String?
    public private(set) var route: LanguageRoute?
    /// The language the term is explained as; preselected from the route, changeable by the learner.
    public var language: LanguageCode? {
        didSet {
            if language != oldValue { languageChanged() }
        }
    }

    public private(set) var phase: Phase = .idle
    public private(set) var insight: WordInsight?
    /// Set when the same word is already saved, so the learner can decide before saving it twice.
    public private(set) var duplicateTranslation: String?
    public private(set) var isLoadingExamples = false
    public private(set) var saveErrorMessage: String?

    public let captureSource: CaptureSource
    private let settings: SettingsStore
    private let destination: any CaptureDestination
    private let makeInsightService: () -> InsightService
    private let router = LanguageRouter()
    private var explainTask: Task<Void, Never>?

    public init(
        text: String = "",
        captureSource: CaptureSource = .text,
        settings: SettingsStore,
        destination: any CaptureDestination,
        insightService: @escaping () -> InsightService
    ) {
        self.captureSource = captureSource
        self.settings = settings
        self.destination = destination
        self.makeInsightService = insightService
        self.text = text
        textChanged()
    }

    // MARK: Selection

    public func tap(tokenAt index: Int) {
        select(TokenSelection.afterTap(on: index, current: selection))
    }

    /// Selects the first word spelled exactly like `term`, as if the learner had tapped it.
    public func selectFirst(matching term: String) {
        if let index = tokens.tokens.firstIndex(where: { $0.text == term }) {
            select(index...index)
        }
    }

    public func select(_ range: ClosedRange<Int>?) {
        explainTask?.cancel()
        selection = range
        insight = nil
        duplicateTranslation = nil
        saveErrorMessage = nil
        guard let range, let term = tokens.term(for: range) else {
            term = nil
            sentence = nil
            route = nil
            language = nil
            phase = .idle
            return
        }
        self.term = term
        let sentence = tokens.sentence(containing: range)
        // A lone word typed by the learner has no sentence to give context.
        self.sentence = sentence.flatMap { $0.matchingKey == term.matchingKey ? nil : $0 }
        guard let profile = settings.profile else { return }
        let route = router.route(self.sentence ?? term, profile: profile)
        self.route = route
        switch route {
        case .confident(let code): language = code
        case .ambiguous(let candidates): language = candidates.first
        case .notLearning: language = nil
        }
        phase = language == nil ? .idle : .ready
    }

    /// Languages to offer as chips, likeliest first.
    public var languageChoices: [LanguageCode] {
        let learning = settings.profile?.learning ?? []
        if case .ambiguous(let candidates) = route {
            return candidates + learning.filter { !candidates.contains($0) }
        }
        return learning
    }

    /// The detected language when the learner doesn't study it yet.
    public var suggestedNewLanguage: LanguageCode? {
        if case .notLearning(let code) = route { return code }
        return nil
    }

    public func addToLearningLanguages(_ code: LanguageCode) {
        guard var profile = settings.profile else { return }
        try? profile.addLearning(code)
        settings.profile = profile
        language = code
    }

    // MARK: Insight

    public var canExplain: Bool {
        term != nil && language != nil && settings.profile != nil && phase != .explaining
    }

    public func explain() {
        guard let term, let language, let native = settings.profile?.native else { return }
        let request = InsightRequest(term: term, sentence: sentence, language: language, nativeLanguage: native)
        let service = makeInsightService()
        explainTask?.cancel()
        phase = .explaining
        explainTask = Task { [weak self] in
            do throws(AIError) {
                let insight = try await service.insight(for: request)
                guard !Task.isCancelled else { return }
                self?.finish(with: insight)
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(error)
            }
        }
    }

    /// Waits for the current explanation; for tests and UI that needs to sequence work.
    public func waitForExplanation() async {
        await explainTask?.value
    }

    private func finish(with insight: WordInsight) {
        self.insight = insight
        duplicateTranslation = destination.savedTranslation(lemma: insight.lemma, language: insight.language)
        phase = .explained
    }

    /// On-device insights come without examples; this asks for them separately.
    public func loadExamples() async {
        guard let insight, insight.examples.isEmpty, !isLoadingExamples else { return }
        isLoadingExamples = true
        defer { isLoadingExamples = false }
        if let updated = try? await makeInsightService().addingExamples(to: insight), self.insight == insight {
            self.insight = updated
        }
    }

    // MARK: Saving

    public func save() {
        guard let insight else { return }
        do {
            try destination.save(insight, captureSource: captureSource)
            saveErrorMessage = nil
            phase = .saved
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    /// Clears everything for the next capture.
    public func reset() {
        text = ""
    }

    // MARK: Private

    private func textChanged() {
        tokens = TokenizedText(text)
        select(tokens.tokens.count == 1 ? 0...0 : nil)
    }

    private func languageChanged() {
        insight = nil
        duplicateTranslation = nil
        if phase != .explaining {
            phase = language == nil ? .idle : .ready
        }
    }
}
