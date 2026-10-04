import Foundation

/// Checks quiz questions before a learner sees them (SPEC C8): four distinct options, exactly one of
/// them right, and a cloze sentence with one blank that doesn't give the word away.
public enum QuizValidator {
    /// The gap in a cloze sentence.
    public static let blank = "____"

    public enum Problem: Error, Equatable, Sendable {
        case notFourOptions
        case emptyPrompt
        case emptyOption
        case answerOutOfRange
        case repeatedOptions
        /// The marked answer isn't the word, or the word's translation.
        case wrongAnswer
        /// Another option is also a form of the word, so two answers would be right.
        case distractorIsTheWord
        /// A cloze sentence needs exactly one blank.
        case missingBlank
        /// The cloze sentence contains the word it asks for.
        case answerInPrompt
    }

    public static func validate(_ question: QuizQuestion, for word: QuizWord) throws(Problem) {
        guard question.options.count == 4 else { throw .notFourOptions }
        guard !question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyPrompt }
        let keys = question.options.map(\.matchingKey)
        guard keys.allSatisfy({ !$0.isEmpty }) else { throw .emptyOption }
        guard question.options.indices.contains(question.answerIndex) else { throw .answerOutOfRange }
        guard Set(keys).count == keys.count else { throw .repeatedOptions }

        let answer = question.correctAnswer
        switch question.kind {
        case .meaning, .listening:
            guard answer.matchingKey == word.translation.matchingKey else { throw .wrongAnswer }
        case .reverse:
            guard isForm(answer, of: word) else { throw .wrongAnswer }
            try checkDistractors(of: question, word: word)
        case .cloze:
            guard question.prompt.components(separatedBy: blank).count == 2 else { throw .missingBlank }
            guard isForm(answer, of: word) else { throw .wrongAnswer }
            try checkDistractors(of: question, word: word)
            let rest = question.prompt.replacingOccurrences(of: blank, with: " ")
            guard !TokenizedText(rest).tokens.contains(where: { isForm($0.text, of: word) }) else { throw .answerInPrompt }
        }
    }

    /// Whether the text is the word or an inflected form of it ("Banken" for "Bank"), ignoring case
    /// and accents. Short words only match exactly or with a short ending.
    public static func isForm(_ text: String, of word: QuizWord) -> Bool {
        [word.term, word.lemma].contains { isForm(text, ofText: $0) }
    }

    /// Whether the text is `form` or an inflected form of it, ignoring case and accents.
    public static func isForm(_ text: String, ofText form: String) -> Bool {
        let candidate = text.matchingKey
        let form = form.matchingKey
        guard !candidate.isEmpty, !form.isEmpty else { return false }
        if candidate == form { return true }
        guard !form.contains(" ") else { return false }
        if form.count >= 4 {
            let stem = String(form.prefix(max(4, form.count - 2)))
            return candidate.hasPrefix(stem) && candidate.count <= form.count + 4
        }
        return candidate.hasPrefix(form) && candidate.count <= form.count + 4
    }

    /// Whether any word of the text is a form of a word in `phrase` ("kahve fincanı" contains
    /// "fincan"). Words shorter than three letters are ignored.
    public static func mentions(_ phrase: String, in text: String) -> Bool {
        let targets = TokenizedText(phrase).tokens.map(\.text).filter { $0.count >= 3 }
        return TokenizedText(text).tokens.contains { token in
            targets.contains { isForm(token.text, ofText: $0) }
        }
    }

    private static func checkDistractors(of question: QuizQuestion, word: QuizWord) throws(Problem) {
        for (index, option) in question.options.enumerated() where index != question.answerIndex {
            if isForm(option, of: word) { throw .distractorIsTheWord }
        }
    }
}
