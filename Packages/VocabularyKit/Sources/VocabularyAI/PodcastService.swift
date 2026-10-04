import Foundation
import FoundationModels
import NaturalLanguage
import VocabularyCore

/// What a podcast should be (SPEC C9).
public struct PodcastRequest: Sendable, Hashable {
    /// The saved words the script must use; 3 to 12.
    public var words: [QuizWord]
    public var language: LanguageCode
    public var nativeLanguage: LanguageCode
    public var level: LanguageLevel
    public var length: PodcastLength
    public var style: PodcastStyle

    public init(
        words: [QuizWord],
        language: LanguageCode,
        nativeLanguage: LanguageCode,
        level: LanguageLevel,
        length: PodcastLength,
        style: PodcastStyle
    ) {
        self.words = words
        self.language = language
        self.nativeLanguage = nativeLanguage
        self.level = level
        self.length = length
        self.style = style
    }
}

/// Writes podcast scripts (SPEC C9, ADR-008). Cloud models write the script in one call. The
/// on-device model drafts it in short parts that each fit its context window, then adds one line for
/// every word the draft left out.
public struct PodcastService: Sendable {
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

    public func script(for request: PodcastRequest) async throws(AIError) -> PodcastScript {
        switch strategy {
        case .singleCall:
            return try await PodcastPrompts.whole(request).run(on: client) { content throws(ValidationFailure) in
                let script = try PodcastParser.script(from: content, style: request.style, title: nil)
                try PodcastParser.check(script, request: request)
                return script
            }
        case .stepwise:
            return try await scriptInParts(for: request)
        }
    }

    private func scriptInParts(for request: PodcastRequest) async throws(AIError) -> PodcastScript {
        let count = PodcastPrompts.partCount(for: request)
        let groups = PodcastPrompts.split(request.words, into: count)
        // Room for one extra line per word, should the draft leave every word out.
        let draftBudget = request.length.maximumWords - PodcastParser.lineWordLimit * request.words.count
        var title: String?
        var parts: [[PodcastSegment]] = []
        for (index, words) in groups.enumerated() {
            let spec = try PodcastPrompts.part(request, number: index + 1, of: count, words: words, title: title)
            let earlier = parts.flatMap { $0 }
            let limit = PodcastParser.wordLimit(
                total: draftBudget, used: PodcastScript(title: "", segments: earlier).wordCount, partsLeft: count - index
            )
            var attempt = 0
            let part: PodcastScript
            do throws(AIError) {
                part = try await spec.run(on: client, attempts: 3) { [title] content throws(ValidationFailure) in
                    attempt += 1
                    let written = try PodcastParser.script(from: content, style: request.style, title: title)
                    // A plain title is better than no episode, so the last attempt keeps whatever came.
                    if title == nil, attempt < 3 {
                        try PodcastParser.checkTitle(written.title, words: request.words, language: request.language)
                    }
                    // Sentences said before, and lines beyond the part's share, are dropped rather than
                    // failing the whole part.
                    let part = PodcastParser.trimmed(PodcastScript(
                        title: written.title,
                        segments: PodcastValidator.removingRepeatedSentences(from: written.segments, after: earlier)
                    ), toWordLimit: limit)
                    try PodcastParser.checkPart(part, request: request, limit: limit)
                    return part
                }
            } catch .guardrailViolation, .refusal {
                // The model's safety rules sometimes stop an ordinary part. It is left out; its words
                // get lines of their own below, and without a title yet, the next part writes one.
                parts.append([])
                continue
            }
            title = title ?? part.title
            parts.append(part.segments)
        }
        guard let title else { throw .guardrailViolation }

        // Each word the draft left out gets one more line in the part meant to use it.
        for (index, words) in groups.enumerated() {
            let draft = PodcastScript(title: "", segments: parts[index])
            for word in PodcastValidator.missingWords(words, in: draft, language: request.language) {
                let earlier = parts.flatMap { $0 }
                let sentence = try await PodcastPrompts.line(request, word: word, title: title).run(on: client, attempts: 3) { content throws(ValidationFailure) in
                    try PodcastParser.line(from: content, word: word, request: request, after: earlier)
                }
                parts[index] = PodcastParser.adding(sentence, to: parts[index], style: request.style)
            }
        }

        let script = PodcastScript(title: title, segments: parts.flatMap { $0 })
        do {
            try PodcastValidator.validate(script, words: request.words, language: request.language, style: request.style, length: request.length)
        } catch {
            throw .invalidOutput(PodcastParser.reason(for: error))
        }
        return script
    }
}

/// Reads and checks what the model wrote (ADR-003, "validation everywhere"). Reasons go back to the
/// model on the retry as instructions.
enum PodcastParser {
    /// - Parameter title: the episode's title when a later part doesn't write one.
    static func script(from content: GeneratedContent, style: PodcastStyle, title: String?) throws(ValidationFailure) -> PodcastScript {
        let title = title ?? InsightValidator.clean(InsightValidator.string("title", in: content))
        guard !title.isEmpty, InsightValidator.wordCount(title) <= 12 else {
            throw ValidationFailure(reason: "title must be a short title")
        }
        var segments: [PodcastSegment] = []
        switch style {
        case .dialogue:
            let lines = (try? content.value([GeneratedContent].self, forProperty: "lines")) ?? []
            for line in lines {
                let speaker = InsightValidator.string("speaker", in: line).lowercased() == "guest" ? PodcastSpeaker.guest : .host
                let text = InsightValidator.clean(InsightValidator.string("text", in: line))
                if !text.isEmpty {
                    segments.append(PodcastSegment(speaker: speaker, text: text))
                }
            }
        case .story:
            let paragraphs = (try? content.value([String].self, forProperty: "paragraphs")) ?? []
            segments = paragraphs.map(InsightValidator.clean).filter { !$0.isEmpty }.map { PodcastSegment(speaker: .narrator, text: $0) }
        }
        guard !segments.isEmpty else {
            throw ValidationFailure(reason: style == .dialogue ? "lines must contain the conversation" : "paragraphs must contain the story")
        }
        return PodcastScript(title: title, segments: segments)
    }

    static func check(_ script: PodcastScript, request: PodcastRequest) throws(ValidationFailure) {
        do {
            try PodcastValidator.validate(script, words: request.words, language: request.language, style: request.style, length: request.length)
        } catch {
            throw ValidationFailure(reason: reason(for: error))
        }
    }

    /// The most words a part may have: up to one and a half times a fair share of what is left, while
    /// leaving every later part at least a few lines, so the whole script stays within the cap.
    static func wordLimit(total: Int, used: Int, partsLeft: Int) -> Int {
        let left = max(0, total - used)
        let fairShare = Double(left) / Double(max(1, partsLeft))
        let reserve = 15 * (partsLeft - 1)
        return max(15, min(Int(fairShare * 1.5), left - reserve))
    }

    /// The most words a line written for a missing word may have; the prompt asks for 15.
    static let lineWordLimit = 20

    /// A title names the topic, in the episode's language. Asked for a topic that fits the words, the
    /// model sometimes made the word list the title, and sometimes wrote it in English.
    static func checkTitle(_ title: String, words: [QuizWord], language: LanguageCode) throws(ValidationFailure) {
        let tokens = TokenizedText(title).tokens
        let listed = words.filter { word in tokens.contains { QuizValidator.isForm($0.text, of: word) } }
        guard listed.count <= 2 else {
            throw ValidationFailure(reason: "the title must name the episode's topic, not list the words")
        }
        // Fewer words are too few to tell a language by; names would pass for anything.
        guard tokens.count >= 3 else { return }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(title)
        if let (detected, probability) = recognizer.languageHypotheses(withMaximum: 1).first,
           probability >= 0.7, !detected.rawValue.hasPrefix(language.languageSubtag) {
            throw ValidationFailure(reason: "the title must be in \(language.englishName)")
        }
    }

    /// The part without its last lines or sentences beyond the limit; at least one sentence stays.
    static func trimmed(_ part: PodcastScript, toWordLimit limit: Int) -> PodcastScript {
        var segments = part.segments
        while PodcastScript(title: "", segments: segments).wordCount > limit, let last = segments.last {
            let sentences = sentences(of: last.text)
            if sentences.count > 1 {
                segments[segments.count - 1].text = sentences.dropLast().joined(separator: " ")
            } else if segments.count > 1 {
                segments.removeLast()
            } else {
                break
            }
        }
        return PodcastScript(title: part.title, segments: segments)
    }

    private static func sentences(of text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).map { text[$0].trimmingCharacters(in: .whitespaces) }
    }

    /// A draft part needs text and no more words than its limit. Words it leaves out get lines of
    /// their own afterwards; both hosts speaking is checked for the whole script, since dropping
    /// repeated sentences can leave a part with one speaker.
    static func checkPart(_ part: PodcastScript, request: PodcastRequest, limit: Int) throws(ValidationFailure) {
        guard !part.segments.isEmpty else {
            throw ValidationFailure(reason: "every sentence must be new; don't repeat sentences")
        }
        guard part.wordCount <= limit else {
            throw ValidationFailure(reason: "this part must be shorter, at most \(limit) words")
        }
    }

    /// The sentence written for a word the draft left out: short, new, and using the word.
    static func line(from content: GeneratedContent, word: QuizWord, request: PodcastRequest, after earlier: [PodcastSegment]) throws(ValidationFailure) -> String {
        let sentence = InsightValidator.clean(InsightValidator.string("sentence", in: content))
        guard !sentence.isEmpty, InsightValidator.wordCount(sentence) <= lineWordLimit else {
            throw ValidationFailure(reason: "sentence must be one short sentence")
        }
        let line = PodcastScript(title: "", segments: [PodcastSegment(speaker: .host, text: sentence)])
        guard PodcastValidator.missingWords([word], in: line, language: request.language).isEmpty else {
            throw ValidationFailure(reason: "sentence must use «\(word.term)»")
        }
        guard !PodcastValidator.repeatsASentence(earlier + line.segments) else {
            throw ValidationFailure(reason: "the sentence must be new")
        }
        return sentence
    }

    /// A dialogue gets the sentence as a new line from the other host; a story adds it to the
    /// part's paragraph.
    static func adding(_ sentence: String, to part: [PodcastSegment], style: PodcastStyle) -> [PodcastSegment] {
        var part = part
        switch style {
        case .dialogue:
            let speaker: PodcastSpeaker = part.last?.speaker == .host ? .guest : .host
            part.append(PodcastSegment(speaker: speaker, text: sentence))
        case .story:
            if let last = part.indices.last {
                part[last].text += " " + sentence
            } else {
                part.append(PodcastSegment(speaker: .narrator, text: sentence))
            }
        }
        return part
    }

    static func reason(for problem: PodcastValidator.Problem) -> String {
        switch problem {
        case .missingTitle: "the script needs a short title"
        case .noSegments, .emptySegment: "every line must have text"
        case .wrongSpeakers: "use the speakers the schema allows, and let both hosts speak in a conversation"
        case .tooLong: "the script is too long; keep to the requested length"
        case .repeatedSentence: "every sentence must be new; don't repeat sentences"
        case .missingWords(let terms): "use each of these words at least once: \(terms.map { "«\($0)»" }.joined(separator: ", "))"
        }
    }
}
