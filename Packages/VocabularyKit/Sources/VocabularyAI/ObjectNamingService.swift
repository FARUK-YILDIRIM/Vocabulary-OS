import Foundation
import FoundationModels
import VocabularyCore

/// A photographed object to name in one of the learner's languages (ADR-005).
public struct ObjectNamingRequest: Sendable, Hashable {
    /// What the object is: the classifier's English label, or what the learner typed.
    public var label: String
    public var language: LanguageCode
    public var nativeLanguage: LanguageCode

    public init(label: String, language: LanguageCode, nativeLanguage: LanguageCode) {
        self.label = label
        self.language = language
        self.nativeLanguage = nativeLanguage
    }
}

/// Names a photographed object in a learning language: the word with the article learners memorize
/// with it, a native translation and meaning, and an example (SPEC C6, ADR-005).
public struct ObjectNamingService: Sendable {
    public let client: any GenerationClient
    public let source: InsightSource

    public init(client: any GenerationClient, source: InsightSource) {
        self.client = client
        self.source = source
    }

    /// Uses the same provider and model as the insight service.
    public init(_ insightService: InsightService) {
        self.init(client: insightService.client, source: insightService.source)
    }

    public func name(_ request: ObjectNamingRequest) async throws(AIError) -> WordInsight {
        let name = try await ObjectNamingPrompts.name(request).run(on: client) { content throws(ValidationFailure) in
            try ObjectNamingValidator.name(content, request: request)
        }
        return WordInsight(
            term: name.term,
            lemma: name.word,
            partOfSpeech: .noun,
            language: request.language,
            nativeLanguage: request.nativeLanguage,
            translation: name.translation,
            meaning: name.meaning,
            examples: name.example.map { [$0] } ?? [],
            source: source
        )
    }
}

/// The object-naming prompt: one small call that suits the on-device model and cloud models alike.
enum ObjectNamingPrompts {
    /// Articles learners memorize with a noun: definite articles where they show gender, and the
    /// indefinite ones of the Scandinavian languages. Languages without articles get none.
    static func articles(for language: LanguageCode) -> [String]? {
        switch language.languageSubtag {
        case "de": ["der", "die", "das"]
        case "fr": ["le", "la", "l'"]
        case "es": ["el", "la"]
        case "it": ["il", "lo", "la", "l'"]
        case "pt": ["o", "a"]
        case "nl": ["de", "het"]
        case "sv": ["en", "ett"]
        case "da": ["en", "et"]
        case "nb": ["en", "ei", "et"]
        default: nil
        }
    }

    static func name(_ request: ObjectNamingRequest) throws(AIError) -> PromptSpec {
        let learning = request.language.englishName
        let native = request.nativeLanguage.englishName
        var properties = [
            InsightPrompts.text("name", "The usual \(learning) word for this object, in the singular, without an article."),
        ]
        if let articles = articles(for: request.language) {
            properties.append(.init(
                name: "article",
                description: "The \(learning) article learners memorize with that word.",
                schema: DynamicGenerationSchema(name: "Article", anyOf: articles)
            ))
        }
        properties += [
            InsightPrompts.text("translation", "The \(native) word for this object, 1 to 3 words."),
            InsightPrompts.text("meaning", "In \(native), one short sentence saying what this object is."),
            InsightPrompts.text("example", "A short, natural \(learning) sentence of at most 10 words that uses the word."),
            InsightPrompts.text("exampleTranslation", "The \(native) translation of that sentence."),
        ]
        return PromptSpec(
            request: GenerationRequest(
                instructions: "You name everyday objects for language learners whose native language is \(native). Write each field in the language it asks for.",
                prompt: "Object: \(request.label). Name it in \(learning).",
                maximumResponseTokens: 300
            ),
            schema: try InsightPrompts.schema("ObjectName", properties)
        )
    }
}

/// Checks a named object before it reaches the learner (ADR-003, "validation everywhere").
enum ObjectNamingValidator {
    struct Name {
        /// The word as learners memorize it, with its article: "die Tasse".
        let term: String
        /// The word alone: "Tasse".
        let word: String
        let translation: String
        let meaning: String
        let example: UsageExample?
    }

    static func name(_ content: GeneratedContent, request: ObjectNamingRequest) throws(ValidationFailure) -> Name {
        var word = InsightValidator.clean(InsightValidator.string("name", in: content))
        var article = InsightValidator.clean(InsightValidator.string("article", in: content)).lowercased()
        let articles = ObjectNamingPrompts.articles(for: request.language)

        // Some answers write the article into the name ("die Tasse"); that is still usable.
        if let articles, let first = word.split(separator: " ").first, articles.contains(first.lowercased()),
           InsightValidator.wordCount(word) > 1 {
            if article.isEmpty { article = first.lowercased() }
            word = word.dropFirst(first.count).trimmingCharacters(in: .whitespaces)
        }
        guard !word.isEmpty, InsightValidator.wordCount(word) <= 4 else {
            throw ValidationFailure(reason: "name must be the object's \(request.language.englishName) word, at most 4 words")
        }
        if let articles {
            guard articles.contains(article) else {
                throw ValidationFailure(reason: "article must be one of \(articles.joined(separator: ", "))")
            }
        } else {
            article = ""
        }

        let translation = InsightValidator.cleanTranslation(InsightValidator.string("translation", in: content))
        guard !translation.isEmpty, InsightValidator.wordCount(translation) <= 4 else {
            throw ValidationFailure(reason: "translation must be 1 to 4 \(request.nativeLanguage.englishName) words, not a sentence")
        }
        let meaning = InsightValidator.clean(InsightValidator.string("meaning", in: content))
        try InsightValidator.checkMeaning(meaning, native: request.nativeLanguage)

        let term = article.isEmpty ? word : (article.hasSuffix("'") ? article + word : "\(article) \(word)")
        return Name(term: term, word: word, translation: translation, meaning: meaning, example: example(in: content, word: word))
    }

    /// The example, if it is short and uses the word; a missing example is not worth a retry.
    private static func example(in content: GeneratedContent, word: String) -> UsageExample? {
        let sentence = InsightValidator.clean(InsightValidator.string("example", in: content))
        let translation = InsightValidator.clean(InsightValidator.string("exampleTranslation", in: content))
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        // Inflected forms ("Tassen") share a stem with the word.
        let stem = String(word.prefix(max(4, word.count - 2)))
        guard !sentence.isEmpty, !translation.isEmpty, InsightValidator.wordCount(sentence) <= 20,
              sentence.range(of: word, options: options) != nil || sentence.range(of: stem, options: options) != nil
        else {
            return nil
        }
        return UsageExample(sentence: sentence, translation: translation)
    }
}
