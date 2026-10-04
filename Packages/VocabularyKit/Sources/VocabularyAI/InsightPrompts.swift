import Foundation
import FoundationModels
import VocabularyCore

/// A request plus the schema its answer must follow.
struct PromptSpec: Sendable {
    var request: GenerationRequest
    var schema: GenerationSchema

    /// The second attempt: sampling instead of greedy decoding (greedy can loop), plus a note on
    /// what was wrong when a validator rejected the first answer.
    func retry(reason: String?) -> PromptSpec {
        var copy = self
        copy.request.isGreedy = false
        copy.request.temperature = 0.4
        let note = reason.map { "Your previous answer was not valid: \($0)." } ?? "Your previous answer could not be read."
        copy.request.prompt += "\n\n\(note) Answer again and follow the field descriptions exactly."
        return copy
    }
}

/// Prompts for meaning in context (ADR-003). The wording, field order and few-shot examples come from
/// measured experiments on the on-device model; change them only together with `vos-eval`.
enum InsightPrompts {
    // MARK: On device, step 1: the sense, in English

    static func sense(_ request: InsightRequest) throws(AIError) -> PromptSpec {
        let source = request.language.englishName
        var properties: [DynamicGenerationSchema.Property] = []
        let prompt: String
        if let sentence = request.sentence {
            properties.append(text("situation", "In English, at most 12 words: what the sentence is about."))
            prompt = "Term: «\(request.term)» Sentence (\(source)): \(marking(request.term, in: sentence))"
        } else {
            prompt = "Term: «\(request.term)» (\(source)). No sentence was given: explain its most common meaning."
        }
        properties += [
            text("englishWord", "The common English word or fixed expression that means the same as the marked term here."),
            text("englishGloss", "In English, 3 to 8 words: a definition of that meaning, not the word itself."),
            partOfSpeech(["noun", "verb", "adjective", "adverb", "phrase", "other"]),
        ]
        return PromptSpec(
            request: GenerationRequest(instructions: senseInstructions, prompt: prompt, maximumResponseTokens: 200),
            schema: try schema("Sense", properties)
        )
    }

    private static let senseInstructions = """
    You help language learners. The learner marked one term in a sentence with « ». Explain only the marked \
    term, never another word of the sentence. Answer in English.

    Examples:
    Term: «bat» Sentence: The «bat» flew out of the cave at night.
    situation: an animal leaves a cave at night; englishWord: bat; englishGloss: a small flying mammal; partOfSpeech: noun
    Term: «Tür» Sentence: Er hat die «Tür» leise zugemacht.
    situation: a man quietly closes a door; englishWord: door; englishGloss: a panel that opens an entrance; partOfSpeech: noun
    Term: «run» Sentence: Who will «run» the meeting tomorrow?
    situation: someone will lead a meeting; englishWord: lead; englishGloss: to be in charge of something; partOfSpeech: verb
    """

    // MARK: On device, step 2: the native-language entry

    static func native(_ request: InsightRequest, sense: InsightValidator.Sense) throws(AIError) -> PromptSpec {
        let source = request.language.englishName
        let native = request.nativeLanguage.englishName
        let context = request.sentence.map { " in: \($0)" } ?? ""
        return PromptSpec(
            request: GenerationRequest(
                instructions: "You write short bilingual dictionary entries for learners whose native language is \(native). Write in \(native).",
                prompt: """
                The \(source) term «\(request.term)» means "\(sense.englishWord)" (\(sense.englishGloss))\(context)
                Give the standard \(native) word for this meaning and a short \(native) definition.
                """,
                maximumResponseTokens: 160
            ),
            schema: try schema("Explanation", [
                text("translation", "The standard \(native) dictionary word for this meaning, 1 to 4 words."),
                text("meaning", "In \(native), at most 12 words: a dictionary definition of this meaning."),
            ])
        )
    }

    // MARK: On device, step 3 (on demand): example sentences

    static func examples(for insight: WordInsight) throws(AIError) -> PromptSpec {
        let source = insight.language.englishName
        let native = insight.nativeLanguage.englishName
        let meaning = insight.englishGloss ?? insight.meaning
        return PromptSpec(
            request: GenerationRequest(
                instructions: "You write example sentences for language learners. Example sentences are in \(source); translations are in \(native).",
                prompt: "Term (\(source)): «\(insight.term)», meaning: \(meaning)",
                maximumResponseTokens: 350
            ),
            schema: try schema("Examples", [
                .init(name: "examples", description: "Two example sentences.", schema: examplesArray(source: source, native: native)),
            ])
        )
    }

    // MARK: Cloud: the whole entry in one call

    static func fullEntry(_ request: InsightRequest) throws(AIError) -> PromptSpec {
        let source = request.language.englishName
        let native = request.nativeLanguage.englishName
        let prompt: String
        if let sentence = request.sentence {
            prompt = "Term: «\(request.term)»\nSentence (\(source)): \(marking(request.term, in: sentence))"
        } else {
            prompt = "Term: «\(request.term)» (\(source)). No sentence was given: explain its most common meaning."
        }
        return PromptSpec(
            request: GenerationRequest(
                instructions: """
                You are a precise bilingual dictionary for language learners whose native language is \(native). \
                The learner marked a \(source) term with « ». Explain only that term, in the sense it has in the sentence. \
                Reply with JSON that matches the schema.
                """,
                prompt: prompt,
                maximumResponseTokens: 900
            ),
            schema: try schema("WordEntry", [
                text("lemma", "The term's \(source) dictionary form: infinitive for verbs, singular for nouns, unchanged for fixed expressions."),
                partOfSpeech(PartOfSpeech.allCases.map(\.rawValue)),
                text("englishGloss", "In English, 3 to 8 words: a definition of the term's meaning in this sentence."),
                text("translation", "The standard \(native) dictionary word for this meaning, 1 to 4 words."),
                text("meaning", "In \(native), at most 15 words: what the term means in this sentence."),
                text("grammarNote", "For \(source) nouns: the dictionary entry with article or gender and plural (e.g. 'der Tisch, die Tische'). Otherwise an empty string."),
                .init(name: "examples", description: "Two new example sentences.", schema: examplesArray(source: source, native: native)),
                .init(
                    name: "otherMeanings",
                    description: "Up to three other common meanings of the term, each 1 to 5 \(native) words; empty if there are none.",
                    schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self), minimumElements: 0, maximumElements: 3)
                ),
            ])
        )
    }

    // MARK: Helpers

    /// Puts « » around the first occurrence of the term, so a small model explains the right word.
    static func marking(_ term: String, in sentence: String) -> String {
        guard let range = sentence.range(of: term) ?? sentence.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return sentence
        }
        return sentence.replacingCharacters(in: range, with: "«\(sentence[range])»")
    }

    private static func examplesArray(source: String, native: String) -> DynamicGenerationSchema {
        DynamicGenerationSchema(
            arrayOf: DynamicGenerationSchema(name: "Example", properties: [
                text("sentence", "A new, natural \(source) sentence of at most 12 words that uses the term with this meaning."),
                text("translation", "The \(native) translation of that sentence."),
            ]),
            minimumElements: 2,
            maximumElements: 2
        )
    }

    static func text(_ name: String, _ description: String) -> DynamicGenerationSchema.Property {
        .init(name: name, description: description, schema: DynamicGenerationSchema(type: String.self))
    }

    private static func partOfSpeech(_ choices: [String]) -> DynamicGenerationSchema.Property {
        .init(
            name: "partOfSpeech",
            description: "Part of speech of the marked term.",
            schema: DynamicGenerationSchema(name: "PartOfSpeech", anyOf: choices)
        )
    }

    static func schema(_ name: String, _ properties: [DynamicGenerationSchema.Property]) throws(AIError) -> GenerationSchema {
        do {
            return try GenerationSchema(root: DynamicGenerationSchema(name: name, properties: properties), dependencies: [])
        } catch {
            throw .unknown("Invalid schema \(name)")
        }
    }
}
