import Foundation
import FoundationModels
import VocabularyCore

/// A term to explain, already routed to one of the learner's languages (ADR-004).
public struct InsightRequest: Sendable, Hashable {
    public var term: String
    public var sentence: String?
    public var language: LanguageCode
    public var nativeLanguage: LanguageCode

    public init(term: String, sentence: String?, language: LanguageCode, nativeLanguage: LanguageCode) {
        self.term = term
        self.sentence = sentence
        self.language = language
        self.nativeLanguage = nativeLanguage
    }
}

/// How to ask the model (ADR-003).
public enum InsightStrategy: Sendable {
    /// Small focused calls with English reasoning first; required for the on-device model.
    case stepwise
    /// One call for the whole entry; for capable cloud models.
    case singleCall
}

/// Produces validated meaning-in-context entries (SPEC C3).
public struct InsightService: Sendable {
    public let client: any GenerationClient
    public let strategy: InsightStrategy
    public let source: InsightSource

    public init(client: any GenerationClient, strategy: InsightStrategy, source: InsightSource) {
        self.client = client
        self.strategy = strategy
        self.source = source
    }

    public func insight(for request: InsightRequest) async throws(AIError) -> WordInsight {
        let analysis = TermAnalysis.analyze(term: request.term, in: request.sentence, language: request.language)
        switch strategy {
        case .stepwise:
            return try await stepwiseInsight(for: request, analysis: analysis)
        case .singleCall:
            return try await singleCallInsight(for: request, analysis: analysis)
        }
    }

    /// Adds example sentences to an existing insight (an extra on-device call; cloud entries already
    /// include them). Examples that don't use the term are dropped.
    public func addingExamples(to insight: WordInsight) async throws(AIError) -> WordInsight {
        let spec = try InsightPrompts.examples(for: insight)
        let examples = try await run(spec) { content throws(InsightValidator.Failure) in
            InsightValidator.examples(in: content, term: insight.term, lemma: insight.lemma, native: insight.nativeLanguage)
        }
        var updated = insight
        updated.examples = examples
        return updated
    }

    // MARK: Strategies

    private func stepwiseInsight(for request: InsightRequest, analysis: TermAnalysis) async throws(AIError) -> WordInsight {
        let sense = try await run(try InsightPrompts.sense(request)) { content throws(InsightValidator.Failure) in
            try InsightValidator.sense(content)
        }
        let explanation: InsightValidator.Explanation
        if request.nativeLanguage.languageSubtag == "en" {
            // The sense step already answers in English.
            explanation = InsightValidator.Explanation(translation: sense.englishWord, meaning: sense.englishGloss)
        } else {
            explanation = try await run(try InsightPrompts.native(request, sense: sense)) { content throws(InsightValidator.Failure) in
                try InsightValidator.explanation(content, request: request)
            }
        }
        return WordInsight(
            term: request.term,
            // The small model's lemmas are unreliable (ADR-003), so only NaturalLanguage's are used.
            lemma: analysis.lemma ?? request.term,
            partOfSpeech: analysis.partOfSpeech ?? sense.partOfSpeech,
            language: request.language,
            nativeLanguage: request.nativeLanguage,
            context: request.sentence,
            translation: explanation.translation,
            meaning: explanation.meaning,
            englishGloss: sense.englishGloss,
            source: source
        )
    }

    private func singleCallInsight(for request: InsightRequest, analysis: TermAnalysis) async throws(AIError) -> WordInsight {
        let entry = try await run(try InsightPrompts.fullEntry(request)) { content throws(InsightValidator.Failure) in
            try InsightValidator.fullEntry(content, request: request)
        }
        return WordInsight(
            term: request.term,
            lemma: entry.lemma ?? analysis.lemma ?? request.term,
            partOfSpeech: entry.partOfSpeech ?? analysis.partOfSpeech,
            language: request.language,
            nativeLanguage: request.nativeLanguage,
            context: request.sentence,
            translation: entry.explanation.translation,
            meaning: entry.explanation.meaning,
            englishGloss: entry.englishGloss,
            grammarNote: entry.grammarNote,
            examples: entry.examples,
            otherMeanings: entry.otherMeanings,
            source: source
        )
    }

    // MARK: Retry

    private func run<Output>(
        _ spec: PromptSpec,
        validate: (GeneratedContent) throws(ValidationFailure) -> Output
    ) async throws(AIError) -> Output {
        try await spec.run(on: client, validate: validate)
    }
}

extension AIError {
    /// Errors a second attempt can fix; availability, keys and quotas won't change on retry.
    var isWorthRetrying: Bool {
        switch self {
        case .invalidOutput, .refusal, .busy: true
        case .server(let status): status >= 500
        default: false
        }
    }
}
