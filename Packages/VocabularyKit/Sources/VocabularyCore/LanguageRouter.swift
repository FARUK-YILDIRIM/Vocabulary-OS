import NaturalLanguage

/// Where a captured text belongs (ADR-004).
public enum LanguageRoute: Hashable, Sendable {
    /// Clearly in this learning language; no question needed.
    case confident(LanguageCode)
    /// Several learning languages are plausible, likeliest first. The UI preselects the first and lets
    /// the learner change it with one tap; the AI model can break the tie.
    case ambiguous([LanguageCode])
    /// Clearly in a catalog language the learner doesn't study yet; offer to add it.
    case notLearning(LanguageCode)
}

/// Routes captured text to one of the learner's languages with on-device language identification.
///
/// Thresholds come from measurements on macOS 26.5 (ADR-004): full sentences are identified almost
/// perfectly, while single words are often shared between languages ("Hand", "Kind", "Bank").
public struct LanguageRouter: Sendable {
    /// Minimum probability to trust the result for a sentence (three or more words).
    public var sentenceThreshold = 0.80
    /// Minimum probability to trust the result for a word or a short phrase.
    public var shortTextThreshold = 0.95

    public init() {}

    public func route(_ text: String, profile: LearnerProfile) -> LanguageRoute {
        let learning = profile.learning
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !learning.isEmpty else { return .ambiguous(learning) }

        let isSentence = TokenizedText(trimmed).tokens.count >= 3
        if isSentence, let detected = hypotheses(for: trimmed, among: nil).first, detected.probability >= sentenceThreshold {
            if learning.contains(detected.language) {
                return .confident(detected.language)
            }
            // Native or unsupported text can't be routed to a learning language automatically, and
            // forcing the recognizer to pick among learning languages would give a confident wrong answer.
            guard detected.language != profile.native, LanguageCatalog.contains(detected.language) else {
                return .ambiguous(learning)
            }
            return .notLearning(detected.language)
        }

        if learning.count == 1, !isSentence {
            return .confident(learning[0])
        }

        let ranked = hypotheses(for: trimmed, among: learning)
        if let best = ranked.first, best.probability >= (isSentence ? sentenceThreshold : shortTextThreshold) {
            return .confident(best.language)
        }
        let order = ranked.map(\.language)
        return .ambiguous(order + learning.filter { !order.contains($0) })
    }

    private struct Hypothesis {
        let language: LanguageCode
        let probability: Double
    }

    /// Hypotheses sorted by probability, limited to `candidates` when given. The recognizer's
    /// constraints bias the result but can still return other languages, so filter explicitly.
    private func hypotheses(for text: String, among candidates: [LanguageCode]?) -> [Hypothesis] {
        let recognizer = NLLanguageRecognizer()
        if let candidates {
            recognizer.languageConstraints = candidates.map { NLLanguage(rawValue: $0.rawValue) }
        }
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: 10)
            .compactMap { language, probability in
                LanguageCode(rawValue: language.rawValue).map { Hypothesis(language: $0, probability: probability) }
            }
            .filter { hypothesis in candidates.map { $0.contains(hypothesis.language) } ?? true }
            .sorted { $0.probability > $1.probability }
    }
}
