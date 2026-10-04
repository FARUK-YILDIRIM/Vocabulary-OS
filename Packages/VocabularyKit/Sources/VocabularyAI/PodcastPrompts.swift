import Foundation
import FoundationModels
import VocabularyCore

/// Podcast script prompts (SPEC C9, ADR-008). Cloud models write the script in one call. The
/// on-device model drafts the script in short parts, then writes one more line for each word the
/// draft left out: asked to use words in a dialogue, it often didn't, while one sentence with a word
/// it writes reliably (measured with `vos-eval podcast`).
enum PodcastPrompts {
    static func instructions(_ request: PodcastRequest) -> String {
        let language = request.language.englishName
        return "You write short podcast scripts for learners of \(language) at CEFR level \(request.level.label). Write only in \(language), in natural sentences a learner at that level understands."
    }

    private static func kind(_ style: PodcastStyle) -> String {
        switch style {
        case .dialogue: "a conversation between two podcast hosts"
        case .story: "a short story told by a narrator"
        }
    }

    private static func wordList(_ words: [QuizWord]) -> String {
        words.map { "«\($0.term)»" }.joined(separator: ", ")
    }

    /// The whole script in one call, for cloud models.
    static func whole(_ request: PodcastRequest) throws(AIError) -> PodcastSpec {
        let prompt = """
            Write \(kind(request.style)) of about \(request.length.targetWords) words, with a short title. \
            Use each of these \(request.language.englishName) words naturally at least once: \(wordList(request.words)).
            """
        return PodcastSpec(
            request: GenerationRequest(
                instructions: instructions(request),
                prompt: prompt,
                maximumResponseTokens: request.length.targetWords * 3 + 200
            ),
            schema: try schema(for: request.style, title: true, language: request.language, turns: 4...80)
        )
    }

    /// Words in a drafted part, about: 3 to 5 short lines (measured with `vos-eval podcast`).
    static let wordsPerPart = 40

    /// How many parts the on-device model writes: enough for the length, at least one per word,
    /// within limits for the length. With a part per word alone, a few words made a short episode.
    static func partCount(for request: PodcastRequest) -> Int {
        let range = request.length == .short ? 2...6 : 4...14
        let forLength = (request.length.targetWords + wordsPerPart - 1) / wordsPerPart
        return min(max(request.words.count, forLength, range.lowerBound), range.upperBound)
    }

    /// One part of the draft, for the on-device model. The first part sees every word, to choose a
    /// topic where they all fit; given only its own word, it chose a topic that excluded the others.
    static func part(
        _ request: PodcastRequest,
        number: Int,
        of count: Int,
        words: [QuizWord],
        title: String?
    ) throws(AIError) -> PodcastSpec {
        // Earlier lines aren't quoted: given the previous line, the model repeated it.
        var lines = ["Write part \(number) of \(count) of \(kind(request.style))."]
        if let title {
            lines.append("The episode is called «\(title)». Say something new in this part.")
        } else {
            lines.append("Choose an everyday topic where these words fit: \(wordList(request.words)). Give the episode a short \(request.language.englishName) title that names the topic.")
        }
        if words.count == 1, let word = words.first {
            lines.append("In this part, use the \(request.language.englishName) word «\(word.term)» naturally.")
        } else if !words.isEmpty {
            lines.append("In this part, use each of these \(request.language.englishName) words naturally: \(wordList(words)).")
        }
        switch request.style {
        case .dialogue: lines.append("Write 3 to 5 short lines, taking turns between the two hosts.")
        case .story: lines.append("Write one paragraph of 4 short sentences.")
        }
        lines.append(number == count ? "End the episode." : "Don't end the episode yet.")
        var generation = GenerationRequest(
            instructions: instructions(request),
            prompt: lines.joined(separator: " "),
            maximumResponseTokens: 400
        )
        // Creative text: greedy decoding repeated the same sentence over and over.
        generation.isGreedy = false
        generation.temperature = 0.7
        return PodcastSpec(
            request: generation,
            schema: try schema(for: request.style, title: title == nil, language: request.language, turns: request.style == .dialogue ? 3...5 : 1...1)
        )
    }

    /// One more line that uses a word the draft left out: a single short sentence with the word is a
    /// task the on-device model does reliably, like example sentences.
    static func line(_ request: PodcastRequest, word: QuizWord, title: String) throws(AIError) -> PodcastSpec {
        let language = request.language.englishName
        var generation = GenerationRequest(
            instructions: instructions(request),
            prompt: "The episode is called «\(title)». Write one more short \(language) sentence for it that uses the word «\(word.term)».",
            maximumResponseTokens: 80
        )
        generation.isGreedy = false
        generation.temperature = 0.5
        return PodcastSpec(
            request: generation,
            schema: try InsightPrompts.schema("PodcastLine", [
                InsightPrompts.text("sentence", "One short \(language) sentence of at most 15 words that uses «\(word.term)»."),
            ])
        )
    }

    /// Splits the words into `count` groups in order, so each part has its own words to use.
    static func split(_ words: [QuizWord], into count: Int) -> [[QuizWord]] {
        let size = max(1, Int((Double(words.count) / Double(count)).rounded(.up)))
        return (0..<count).map { index in
            Array(words.dropFirst(index * size).prefix(size))
        }
    }

    private static func schema(for style: PodcastStyle, title: Bool, language: LanguageCode, turns: ClosedRange<Int>) throws(AIError) -> GenerationSchema {
        var properties: [DynamicGenerationSchema.Property] = []
        if title {
            properties.append(InsightPrompts.text("title", "A short \(language.englishName) title for the episode."))
        }
        switch style {
        case .dialogue:
            let line = DynamicGenerationSchema(name: "Line", properties: [
                .init(name: "speaker", description: "Who speaks.", schema: DynamicGenerationSchema(name: "Speaker", anyOf: ["host", "guest"])),
                InsightPrompts.text("text", "What they say: one short sentence."),
            ])
            properties.append(.init(
                name: "lines",
                description: "The conversation, turn by turn, with both hosts taking part.",
                schema: DynamicGenerationSchema(arrayOf: line, minimumElements: turns.lowerBound, maximumElements: turns.upperBound)
            ))
        case .story:
            properties.append(.init(
                name: "paragraphs",
                description: "The story, paragraph by paragraph.",
                schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self), minimumElements: turns.lowerBound, maximumElements: turns.upperBound)
            ))
        }
        return try InsightPrompts.schema(title ? "PodcastScript" : "PodcastPart", properties)
    }
}

typealias PodcastSpec = PromptSpec
