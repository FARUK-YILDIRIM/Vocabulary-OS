import Foundation
import FoundationModels
import VocabularyCore

/// A question to write: what to ask about which word.
public struct QuizPlanItem: Sendable, Hashable {
    public var kind: QuizKind
    public var word: QuizWord

    public init(kind: QuizKind, word: QuizWord) {
        self.kind = kind
        self.word = word
    }
}

/// Writes quiz questions (SPEC C8). The model writes a new sentence for every cloze question.
/// Distractors come from the learner's other saved words when there are enough, because a model's
/// distractors are sometimes synonyms of the answer or in the wrong language (measured with
/// `vos-eval quiz`); with a small library the model writes them too. Every question passes
/// `QuizValidator`; when the model fails, the caller builds the question with `QuizBuilder.fallback`.
public struct QuizService: Sendable {
    public let client: any GenerationClient
    public let strategy: InsightStrategy
    public let source: InsightSource

    public init(client: any GenerationClient, strategy: InsightStrategy, source: InsightSource) {
        self.client = client
        self.strategy = strategy
        self.source = source
    }

    /// Uses the same provider, model and strategy as the insight service.
    public init(_ insightService: InsightService) {
        self.init(client: insightService.client, strategy: insightService.strategy, source: insightService.source)
    }

    /// One question, with at most one small model call, which suits the on-device model: the first
    /// question of a quiz appears without waiting for the others.
    /// - Parameter library: the learner's saved words, the source of distractors.
    public func question(_ kind: QuizKind, for word: QuizWord, library: [QuizWord]) async throws(AIError) -> QuizQuestion {
        var generator = SystemRandomNumberGenerator()
        switch kind {
        case .meaning, .listening:
            if let local = QuizBuilder.fallback(kind, for: word, library: library, using: &generator) {
                return local
            }
            return try await QuizPrompts.meaning(word).run(on: client) { content throws(ValidationFailure) in
                let distractors = try QuizPartsValidator.distractors(in: content, key: "distractors", answer: word.translation, word: nil)
                return try QuizPartsValidator.checked(
                    QuizBuilder.question(kind, for: word, prompt: word.term, answer: word.translation, distractors: distractors, using: &generator),
                    word: word
                )
            }
        case .reverse:
            if let local = QuizBuilder.fallback(.reverse, for: word, library: library, using: &generator) {
                return local
            }
            return try await QuizPrompts.reverse(word).run(on: client) { content throws(ValidationFailure) in
                let distractors = try QuizPartsValidator.distractors(in: content, key: "distractors", answer: word.term, word: word)
                return try QuizPartsValidator.checked(
                    QuizBuilder.question(.reverse, for: word, prompt: word.translation, answer: word.term, distractors: distractors, using: &generator),
                    word: word
                )
            }
        case .cloze:
            return try await QuizPrompts.cloze(word).run(on: client) { content throws(ValidationFailure) in
                let cloze = try QuizPartsValidator.cloze(in: content, key: "sentence", word: word)
                let distractors: [String]
                if let local = QuizBuilder.distractors(.cloze, for: word, answer: cloze.answer, library: library, using: &generator) {
                    distractors = local
                } else {
                    distractors = try QuizPartsValidator.distractors(in: content, key: "distractors", answer: cloze.answer, word: word)
                }
                return try QuizPartsValidator.checked(
                    QuizBuilder.question(.cloze, for: word, prompt: cloze.prompt, answer: cloze.answer, distractors: distractors, using: &generator),
                    word: word
                )
            }
        }
    }

    /// The questions of a quiz with at most one call, for cloud models. Questions whose parts
    /// aren't valid are left out, in plan order, for the caller to build locally.
    public func questions(for plan: [QuizPlanItem], library: [QuizWord]) async throws(AIError) -> [QuizQuestion] {
        var generator = SystemRandomNumberGenerator()
        // Only cloze sentences, and distractors the library can't supply, need the model.
        let needsModel = plan.filter { item in
            item.kind == .cloze || QuizBuilder.fallback(item.kind, for: item.word, library: library, using: &generator) == nil
        }
        var words: [QuizWord] = []
        for item in needsModel where !words.contains(item.word) {
            words.append(item.word)
        }
        var parts: [GeneratedContent?] = []
        if !words.isEmpty {
            parts = try await QuizPrompts.batch(words).run(on: client) { content throws(ValidationFailure) in
                try QuizPartsValidator.batch(content, wordCount: words.count)
            }
        }
        return plan.compactMap { item in
            if item.kind != .cloze, let local = QuizBuilder.fallback(item.kind, for: item.word, library: library, using: &generator) {
                return local
            }
            guard let index = words.firstIndex(of: item.word), let content = parts[index] else { return nil }
            return question(item.kind, for: item.word, from: content, library: library, using: &generator)
        }
    }

    private func question(
        _ kind: QuizKind,
        for word: QuizWord,
        from content: GeneratedContent,
        library: [QuizWord],
        using generator: inout SystemRandomNumberGenerator
    ) -> QuizQuestion? {
        let question: QuizQuestion
        do throws(ValidationFailure) {
            switch kind {
            case .meaning, .listening:
                let distractors = try QuizPartsValidator.distractors(in: content, key: "meaningDistractors", answer: word.translation, word: nil)
                question = QuizBuilder.question(kind, for: word, prompt: word.term, answer: word.translation, distractors: distractors, using: &generator)
            case .reverse:
                let distractors = try QuizPartsValidator.distractors(in: content, key: "termDistractors", answer: word.term, word: word)
                question = QuizBuilder.question(.reverse, for: word, prompt: word.translation, answer: word.term, distractors: distractors, using: &generator)
            case .cloze:
                let cloze = try QuizPartsValidator.cloze(in: content, key: "clozeSentence", word: word)
                let distractors: [String]
                if let local = QuizBuilder.distractors(.cloze, for: word, answer: cloze.answer, library: library, using: &generator) {
                    distractors = local
                } else {
                    distractors = try QuizPartsValidator.distractors(in: content, key: "termDistractors", answer: cloze.answer, word: word)
                }
                question = QuizBuilder.question(.cloze, for: word, prompt: cloze.prompt, answer: cloze.answer, distractors: distractors, using: &generator)
            }
            return try QuizPartsValidator.checked(question, word: word)
        } catch {
            return nil
        }
    }
}

/// Checks what the model wrote for a quiz (ADR-003, "validation everywhere"). Reasons go back to the
/// model on the retry, so they are instructions and never quote the learner's words.
enum QuizPartsValidator {
    /// Three usable wrong answers from the model's (up to four), dropping ones that repeat or contain
    /// the right answer: "kahve fincanı" for "fincan", or "Bir elma" for a German word meaning "elma".
    static func distractors(in content: GeneratedContent, key: String, answer: String, word: QuizWord?) throws(ValidationFailure) -> [String] {
        let raw = (try? content.value([String].self, forProperty: key)) ?? []
        var seen: Set<String> = [answer.matchingKey]
        var usable: [String] = []
        for candidate in raw.map(InsightValidator.clean) where !candidate.isEmpty && InsightValidator.wordCount(candidate) <= 4 {
            let key = candidate.matchingKey
            guard !seen.contains(key), !QuizValidator.mentions(answer, in: candidate) else { continue }
            if let word, QuizValidator.isForm(candidate, of: word) || QuizValidator.mentions(word.translation, in: candidate) {
                continue
            }
            seen.insert(key)
            usable.append(candidate)
        }
        guard usable.count >= 3 else {
            throw ValidationFailure(reason: "\(key) must be words for other things, all different, without the right answer in them")
        }
        return Array(usable.prefix(3))
    }

    static func cloze(in content: GeneratedContent, key: String, word: QuizWord) throws(ValidationFailure) -> (prompt: String, answer: String) {
        let sentence = InsightValidator.clean(InsightValidator.string(key, in: content))
        guard !sentence.isEmpty, InsightValidator.wordCount(sentence) <= 20 else {
            throw ValidationFailure(reason: "\(key) must be one short sentence")
        }
        guard let cloze = QuizBuilder.cloze(sentence, for: word) else {
            throw ValidationFailure(reason: "\(key) must use the target word")
        }
        return cloze
    }

    static func checked(_ question: QuizQuestion, word: QuizWord) throws(ValidationFailure) -> QuizQuestion {
        do {
            try QuizValidator.validate(question, for: word)
            return question
        } catch {
            throw ValidationFailure(reason: "the question is not valid (\(error))")
        }
    }

    /// The parts for each word, by list position; a word with no item gets `nil`.
    static func batch(_ content: GeneratedContent, wordCount: Int) throws(ValidationFailure) -> [GeneratedContent?] {
        guard let items = try? content.value([GeneratedContent].self, forProperty: "items"), !items.isEmpty else {
            throw ValidationFailure(reason: "items must list every word")
        }
        var parts = [GeneratedContent?](repeating: nil, count: wordCount)
        for item in items {
            guard let number = try? item.value(Int.self, forProperty: "word"), (1...wordCount).contains(number) else { continue }
            parts[number - 1] = item
        }
        return parts
    }
}
