import Foundation
import Testing
@testable import VocabularyCore

/// A deterministic generator, so option order is the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

enum QuizSamples {
    static func word(_ term: String, _ translation: String, _ language: LanguageCode = .english, context: String? = nil) -> QuizWord {
        QuizWord(id: UUID(), term: term, lemma: term, language: language, nativeLanguage: .turkish,
                 translation: translation, meaning: "Anlam.", context: context, partOfSpeech: .noun)
    }

    static let bench = word("Bank", "bank", .german, context: "Wir saßen auf einer alten Bank im Park.")
    static let library = [
        bench,
        word("Schlüssel", "anahtar", .german, context: "Ich habe meinen Schlüssel vergessen."),
        word("Tasse", "fincan", .german),
        word("Zug", "tren", .german),
        word("Apfel", "elma", .german),
        word("cookies", "çerez", .english, context: "This website uses cookies."),
    ]
}

@Suite struct QuizValidatorTests {
    private let word = QuizSamples.bench

    private func question(_ kind: QuizKind = .meaning, prompt: String = "Bank", options: [String] = ["bank", "tren", "elma", "kapı"], answer: Int = 0) -> QuizQuestion {
        QuizQuestion(kind: kind, wordID: word.id, prompt: prompt, options: options, answerIndex: answer)
    }

    @Test func acceptsAWellFormedQuestionOfEachKind() throws {
        try QuizValidator.validate(question(.meaning), for: word)
        try QuizValidator.validate(question(.listening), for: word)
        try QuizValidator.validate(question(.reverse, prompt: "bank", options: ["Zug", "Bank", "Apfel", "Tür"], answer: 1), for: word)
        try QuizValidator.validate(question(.cloze, prompt: "Wir sitzen auf der \(QuizValidator.blank).", options: ["Zug", "Apfel", "Bank", "Tür"], answer: 2), for: word)
        // An inflected form fits a cloze sentence.
        try QuizValidator.validate(question(.cloze, prompt: "Im Park stehen viele \(QuizValidator.blank).", options: ["Züge", "Banken", "Äpfel", "Türen"], answer: 1), for: word)
    }

    @Test func rejectsADistractorThatIsAlsoAFormOfTheWord() {
        // Both would fit the blank, so the question would have two right answers.
        #expect(throws: QuizValidator.Problem.distractorIsTheWord) {
            try QuizValidator.validate(question(.cloze, prompt: "Im Park stehen viele \(QuizValidator.blank).", options: ["Bänke", "Banken", "Züge", "Äpfel"], answer: 1), for: word)
        }
        #expect(throws: QuizValidator.Problem.distractorIsTheWord) {
            try QuizValidator.validate(question(.reverse, prompt: "bank", options: ["Bank", "Banken", "Zug", "Tür"], answer: 0), for: word)
        }
    }

    @Test(arguments: [
        (["bank", "tren", "elma"], 0, QuizValidator.Problem.notFourOptions),
        (["bank", "tren", "elma", "kapı", "masa"], 0, .notFourOptions),
        (["bank", " ", "elma", "kapı"], 0, .emptyOption),
        (["bank", "Tren", "elma", "tren"], 0, .repeatedOptions),
        (["bank", "Bánk", "elma", "kapı"], 0, .repeatedOptions),
        (["bank", "tren", "elma", "kapı"], 4, .answerOutOfRange),
        (["tren", "bank", "elma", "kapı"], 0, .wrongAnswer),
    ])
    func rejectsMalformedOptions(options: [String], answer: Int, problem: QuizValidator.Problem) {
        #expect(throws: problem) {
            try QuizValidator.validate(question(options: options, answer: answer), for: word)
        }
    }

    @Test func rejectsAnEmptyPrompt() {
        #expect(throws: QuizValidator.Problem.emptyPrompt) {
            try QuizValidator.validate(question(prompt: "  "), for: word)
        }
    }

    @Test func rejectsAReverseQuestionWhoseAnswerIsNotTheWord() {
        #expect(throws: QuizValidator.Problem.wrongAnswer) {
            try QuizValidator.validate(question(.reverse, prompt: "bank", options: ["Zug", "Bank", "Apfel", "Tür"], answer: 0), for: word)
        }
    }

    @Test(arguments: [
        ("Wir sitzen im Park.", QuizValidator.Problem.missingBlank),
        ("Die \(QuizValidator.blank) steht neben der \(QuizValidator.blank).", .missingBlank),
        ("Die Bank steht im Park, wir sitzen auf der \(QuizValidator.blank).", .answerInPrompt),
    ])
    func rejectsMalformedClozeSentences(prompt: String, problem: QuizValidator.Problem) {
        #expect(throws: problem) {
            try QuizValidator.validate(question(.cloze, prompt: prompt, options: ["Zug", "Bank", "Apfel", "Tür"], answer: 1), for: word)
        }
    }

    @Test func rejectsAClozeAnswerThatIsAnotherWord() {
        #expect(throws: QuizValidator.Problem.wrongAnswer) {
            try QuizValidator.validate(question(.cloze, prompt: "Wir fahren mit dem \(QuizValidator.blank).", options: ["Zug", "Bank", "Apfel", "Tür"], answer: 0), for: word)
        }
    }
}

@Suite struct QuizBuilderTests {
    @Test func blanksTheWordInASentence() throws {
        let cloze = try #require(QuizBuilder.cloze("Wir saßen auf einer alten Bank im Park.", for: QuizSamples.bench))
        #expect(cloze.prompt == "Wir saßen auf einer alten \(QuizValidator.blank) im Park.")
        #expect(cloze.answer == "Bank")

        let inflected = try #require(QuizBuilder.cloze("Die Banken im Park sind neu.", for: QuizSamples.bench))
        #expect(inflected.answer == "Banken")
        #expect(QuizBuilder.cloze("Der Zug kommt.", for: QuizSamples.bench) == nil)
    }

    @Test func placesTheAnswerAmongTheDistractors() throws {
        var generator = SeededGenerator(seed: 7)
        let question = QuizBuilder.question(.meaning, for: QuizSamples.bench, prompt: "Bank", answer: "bank",
                                            distractors: ["tren", "elma", "kapı"], using: &generator)
        #expect(Set(question.options) == ["bank", "tren", "elma", "kapı"])
        #expect(question.correctAnswer == "bank")
        try QuizValidator.validate(question, for: QuizSamples.bench)
    }

    @Test(arguments: QuizKind.allCases)
    func fallbackQuestionsFromSavedWordsAreAlwaysValid(kind: QuizKind) throws {
        var generator = SeededGenerator(seed: 42)
        // A cloze question needs the word's saved sentence.
        let words = QuizSamples.library.filter { $0.language == .german && (kind != .cloze || $0.context != nil) }
        for word in words {
            let question = try #require(QuizBuilder.fallback(kind, for: word, library: QuizSamples.library, using: &generator))
            try QuizValidator.validate(question, for: word)
        }
    }

    @Test func fallbackNeedsASentenceForClozeAndThreeOtherWords() {
        var generator = SeededGenerator(seed: 1)
        let tasse = QuizSamples.library[2]
        #expect(QuizBuilder.fallback(.cloze, for: tasse, library: QuizSamples.library, using: &generator) == nil)
        let tooFew = Array(QuizSamples.library.prefix(3))
        #expect(QuizBuilder.fallback(.meaning, for: QuizSamples.bench, library: tooFew, using: &generator) == nil)
    }

    @Test func fallbackDistractorsComeFromTheSameLanguages() throws {
        var generator = SeededGenerator(seed: 3)
        let reverse = try #require(QuizBuilder.fallback(.reverse, for: QuizSamples.bench, library: QuizSamples.library, using: &generator))
        #expect(!reverse.options.contains("cookies"), "English words don't belong in a German question")
    }
}
