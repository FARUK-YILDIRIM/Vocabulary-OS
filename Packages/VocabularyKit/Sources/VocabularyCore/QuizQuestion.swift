import Foundation

/// What a quiz question asks (SPEC C8).
public enum QuizKind: String, CaseIterable, Codable, Sendable {
    /// The word is shown; the learner picks its meaning in the native language.
    case meaning
    /// The native translation is shown; the learner picks the word.
    case reverse
    /// A new sentence with a blank; the learner picks the word that fits.
    case cloze
    /// The word is spoken; the learner picks its meaning.
    case listening
}

/// A saved word as practice sees it: quizzes ask about it and podcasts use it.
public struct QuizWord: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var term: String
    public var lemma: String
    public var language: LanguageCode
    public var nativeLanguage: LanguageCode
    public var translation: String
    public var meaning: String
    /// The sentence the word was captured from, if any.
    public var context: String?
    public var partOfSpeech: PartOfSpeech?

    public init(
        id: UUID,
        term: String,
        lemma: String,
        language: LanguageCode,
        nativeLanguage: LanguageCode,
        translation: String,
        meaning: String,
        context: String? = nil,
        partOfSpeech: PartOfSpeech? = nil
    ) {
        self.id = id
        self.term = term
        self.lemma = lemma
        self.language = language
        self.nativeLanguage = nativeLanguage
        self.translation = translation
        self.meaning = meaning
        self.context = context
        self.partOfSpeech = partOfSpeech
    }
}

/// One multiple-choice question about a word (SPEC C8).
public struct QuizQuestion: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var kind: QuizKind
    public var wordID: UUID
    /// What the learner reads, or hears for a listening question.
    public var prompt: String
    public var options: [String]
    public var answerIndex: Int

    public init(id: UUID = UUID(), kind: QuizKind, wordID: UUID, prompt: String, options: [String], answerIndex: Int) {
        self.id = id
        self.kind = kind
        self.wordID = wordID
        self.prompt = prompt
        self.options = options
        self.answerIndex = answerIndex
    }

    public var correctAnswer: String {
        options.indices.contains(answerIndex) ? options[answerIndex] : ""
    }
}
