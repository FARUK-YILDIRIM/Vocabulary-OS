import Foundation
import FoundationModels
import VocabularyCore

/// Quiz prompts (SPEC C8). The model never decides the right answer: it writes distractors and cloze
/// sentences around a word whose translation is already saved.
enum QuizPrompts {
    private static func instructions(_ word: QuizWord) -> String {
        "You write multiple-choice quiz options for language learners whose native language is \(word.nativeLanguage.englishName). Write each field in the language it asks for."
    }

    private static func kind(of word: QuizWord) -> String {
        word.partOfSpeech.map { " (\($0.rawValue))" } ?? ""
    }

    /// Wrong answers for a meaning or listening question, in the native language.
    static func meaning(_ word: QuizWord) throws(AIError) -> PromptSpec {
        let native = word.nativeLanguage.englishName
        return PromptSpec(
            request: GenerationRequest(
                instructions: instructions(word),
                prompt: "Word (\(word.language.englishName)): «\(word.term)»\(kind(of: word)). The right answer is its \(native) translation «\(word.translation)».",
                maximumResponseTokens: 120
            ),
            schema: try InsightPrompts.schema("MeaningOptions", [
                .init(name: "distractors", description: "Four wrong answers: \(native) words for four other things of the same kind. Not «\(word.translation)», not its synonyms, and not phrases that contain it.", schema: wrongAnswers),
            ])
        )
    }

    /// Wrong answers for a reverse question, in the learning language.
    static func reverse(_ word: QuizWord) throws(AIError) -> PromptSpec {
        let learning = word.language.englishName
        return PromptSpec(
            request: GenerationRequest(
                instructions: instructions(word),
                prompt: "\(word.nativeLanguage.englishName) «\(word.translation)» is «\(word.term)»\(kind(of: word)) in \(learning). The right answer is «\(word.term)».",
                maximumResponseTokens: 120
            ),
            schema: try InsightPrompts.schema("TermOptions", [
                .init(name: "distractors", description: "Four wrong answers: \(learning) words for four other things of the same kind. Not «\(word.term)», not its synonyms, and not \(word.nativeLanguage.englishName) words.", schema: wrongAnswers),
            ])
        )
    }

    /// A new sentence that uses the word, and words that don't fit it.
    static func cloze(_ word: QuizWord) throws(AIError) -> PromptSpec {
        let learning = word.language.englishName
        return PromptSpec(
            request: GenerationRequest(
                instructions: instructions(word),
                prompt: "Word (\(learning)): «\(word.term)»\(kind(of: word)), meaning «\(word.translation)» in \(word.nativeLanguage.englishName).",
                maximumResponseTokens: 160
            ),
            schema: try InsightPrompts.schema("Cloze", [
                InsightPrompts.text("sentence", "A new, natural \(learning) sentence of at most 12 words that uses «\(word.term)» with this meaning."),
                .init(name: "distractors", description: "Four wrong answers: \(learning) words of the same kind as «\(word.term)» that would make the sentence wrong. Not «\(word.term)» and not \(word.nativeLanguage.englishName) words.", schema: wrongAnswers),
            ])
        )
    }

    /// Everything a quiz needs for several words, in one call for cloud models.
    static func batch(_ words: [QuizWord]) throws(AIError) -> PromptSpec {
        let list = words.enumerated().map { index, word in
            "\(index + 1). «\(word.term)»\(kind(of: word)) in \(word.language.englishName), meaning «\(word.translation)» in \(word.nativeLanguage.englishName)"
        }
        let item = DynamicGenerationSchema(name: "QuizWordParts", properties: [
            .init(name: "word", description: "The word's number in the list.", schema: DynamicGenerationSchema(type: Int.self)),
            .init(name: "meaningDistractors", description: "Four wrong answers in the learner's native language: words for four other things of the same kind, not synonyms of the translation.", schema: wrongAnswers),
            .init(name: "termDistractors", description: "Four wrong answers in the word's language: words for four other things of the same kind, not synonyms of the word.", schema: wrongAnswers),
            InsightPrompts.text("clozeSentence", "A new, natural sentence of at most 12 words in the word's language that uses the word with this meaning."),
        ])
        return PromptSpec(
            request: GenerationRequest(
                instructions: "You write multiple-choice quiz options for language learners. Reply with JSON that matches the schema, with one item for every word in the list.",
                prompt: list.joined(separator: "\n"),
                maximumResponseTokens: 160 * words.count + 200
            ),
            schema: try InsightPrompts.schema("QuizBatch", [
                .init(name: "items", description: "One item per word, in list order.", schema: DynamicGenerationSchema(arrayOf: item)),
            ])
        )
    }

    /// Four asked for, so one can be dropped by the validator and three remain.
    private static var wrongAnswers: DynamicGenerationSchema {
        DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self), minimumElements: 3, maximumElements: 4)
    }
}
