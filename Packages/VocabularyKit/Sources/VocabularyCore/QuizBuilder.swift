import Foundation

/// Assembles quiz questions (SPEC C8). The right answer always comes from the saved word; a model
/// only supplies distractors and cloze sentences, and the local fallback takes them from other saved
/// words.
public enum QuizBuilder {
    /// A question with the answer at a random place among three distractors.
    public static func question(
        _ kind: QuizKind,
        for word: QuizWord,
        prompt: String,
        answer: String,
        distractors: [String],
        using generator: inout some RandomNumberGenerator
    ) -> QuizQuestion {
        var options = Array(distractors.prefix(3))
        let index = Int.random(in: 0...options.count, using: &generator)
        options.insert(answer, at: index)
        return QuizQuestion(kind: kind, wordID: word.id, prompt: prompt, options: options, answerIndex: index)
    }

    /// The sentence with the word replaced by a blank, and the form of the word it used; `nil` when the
    /// sentence doesn't contain the word.
    public static func cloze(_ sentence: String, for word: QuizWord) -> (prompt: String, answer: String)? {
        if word.term.contains(" ") {
            guard let range = sentence.range(of: word.term, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
            return (sentence.replacingCharacters(in: range, with: QuizValidator.blank), String(sentence[range]))
        }
        guard let token = TokenizedText(sentence).tokens.first(where: { QuizValidator.isForm($0.text, of: word) }) else {
            return nil
        }
        return (sentence.replacingCharacters(in: token.range, with: QuizValidator.blank), token.text)
    }

    /// A question built only from saved words: distractors are other words' translations, or other
    /// words in the same language. `nil` without three usable distractors, or without a sentence for
    /// a cloze question.
    public static func fallback(
        _ kind: QuizKind,
        for word: QuizWord,
        library: [QuizWord],
        using generator: inout some RandomNumberGenerator
    ) -> QuizQuestion? {
        switch kind {
        case .meaning, .listening, .reverse:
            let answer = kind == .reverse ? word.term : word.translation
            guard let distractors = distractors(kind, for: word, answer: answer, library: library, using: &generator) else { return nil }
            return question(kind, for: word, prompt: kind == .reverse ? word.translation : word.term, answer: answer,
                            distractors: distractors, using: &generator)
        case .cloze:
            guard let sentence = word.context, let cloze = cloze(sentence, for: word),
                  let distractors = distractors(.cloze, for: word, answer: cloze.answer, library: library, using: &generator)
            else { return nil }
            return question(.cloze, for: word, prompt: cloze.prompt, answer: cloze.answer, distractors: distractors, using: &generator)
        }
    }

    /// Three wrong answers taken from the learner's other saved words: their translations for a
    /// meaning or listening question, words in the same language otherwise. They mean clearly
    /// different things, which a model's distractors don't always do. `nil` with too few words.
    public static func distractors(
        _ kind: QuizKind,
        for word: QuizWord,
        answer: String,
        library: [QuizWord],
        using generator: inout some RandomNumberGenerator
    ) -> [String]? {
        let others = library.filter { $0.id != word.id }
        switch kind {
        case .meaning, .listening:
            let candidates = others.filter { $0.nativeLanguage == word.nativeLanguage }.map(\.translation)
            return pick(3, from: candidates, avoiding: answer, word: nil, using: &generator)
        case .reverse:
            let candidates = others.filter { $0.language == word.language }.map(\.term)
            return pick(3, from: candidates, avoiding: answer, word: word, using: &generator)
        case .cloze:
            // Phrases rarely fit a one-word gap.
            let candidates = others.filter { $0.language == word.language && !$0.term.contains(" ") }.map(\.term)
            return pick(3, from: candidates, avoiding: answer, word: word, using: &generator)
        }
    }

    /// Distinct candidates that aren't the answer, nor a form of the word when one is given.
    static func pick(
        _ count: Int,
        from candidates: [String],
        avoiding answer: String,
        word: QuizWord?,
        using generator: inout some RandomNumberGenerator
    ) -> [String]? {
        var seen: Set<String> = [answer.matchingKey]
        var picked: [String] = []
        for candidate in candidates.shuffled(using: &generator) {
            let key = candidate.matchingKey
            guard !key.isEmpty, !seen.contains(key) else { continue }
            if let word, QuizValidator.isForm(candidate, of: word) { continue }
            seen.insert(key)
            picked.append(candidate)
            if picked.count == count { return picked }
        }
        return nil
    }
}
