import Foundation
import FoundationModels
import NaturalLanguage
import VocabularyCore

/// Cleans and checks model output before it reaches the learner (ADR-003, "validation everywhere").
enum InsightValidator {
    typealias Failure = ValidationFailure

    struct Sense {
        let englishWord: String
        let englishGloss: String
        let partOfSpeech: PartOfSpeech?
    }

    struct Explanation {
        let translation: String
        let meaning: String
    }

    // MARK: Steps

    static func sense(_ content: GeneratedContent) throws(Failure) -> Sense {
        let word = clean(string("englishWord", in: content))
        let gloss = clean(string("englishGloss", in: content))
        guard !word.isEmpty, wordCount(word) <= 6 else { throw Failure(reason: "englishWord must be one English word or short expression") }
        guard !gloss.isEmpty, wordCount(gloss) <= 25 else { throw Failure(reason: "englishGloss must be a short English definition") }
        return Sense(englishWord: word, englishGloss: gloss, partOfSpeech: partOfSpeech(in: content))
    }

    static func explanation(_ content: GeneratedContent, request: InsightRequest) throws(Failure) -> Explanation {
        let translation = cleanTranslation(string("translation", in: content))
        let meaning = clean(string("meaning", in: content))
        try checkTranslation(translation, request: request)
        try checkMeaning(meaning, native: request.nativeLanguage)
        return Explanation(translation: translation, meaning: meaning)
    }

    struct FullEntry {
        let lemma: String?
        let partOfSpeech: PartOfSpeech?
        let englishGloss: String?
        let explanation: Explanation
        let grammarNote: String?
        let examples: [UsageExample]
        let otherMeanings: [String]
    }

    static func fullEntry(_ content: GeneratedContent, request: InsightRequest) throws(Failure) -> FullEntry {
        let explanation = try explanation(content, request: request)
        let lemma = clean(string("lemma", in: content))
        let gloss = clean(string("englishGloss", in: content))
        let grammar = clean(string("grammarNote", in: content))
        return FullEntry(
            lemma: lemma.isEmpty || wordCount(lemma) > 5 ? nil : lemma,
            partOfSpeech: partOfSpeech(in: content),
            englishGloss: gloss.isEmpty ? nil : gloss,
            explanation: explanation,
            grammarNote: grammar.isEmpty || wordCount(grammar) > 15 ? nil : grammar,
            examples: examples(in: content, term: request.term, lemma: lemma, native: request.nativeLanguage),
            otherMeanings: otherMeanings(in: content, excluding: [explanation.translation, request.term], native: request.nativeLanguage)
        )
    }

    /// Keeps only examples that actually use the term and whose translation reads as the native
    /// language; never fails the whole insight because of one weak example.
    static func examples(in content: GeneratedContent, term: String, lemma: String?, native: LanguageCode) -> [UsageExample] {
        let items = (try? content.value([GeneratedContent].self, forProperty: "examples")) ?? []
        return items.compactMap { item -> UsageExample? in
            let sentence = clean(string("sentence", in: item))
            let translation = clean(string("translation", in: item))
            guard !sentence.isEmpty, !translation.isEmpty, wordCount(sentence) <= 25,
                  uses(term: term, lemma: lemma, in: sentence),
                  isPlausibly(translation, in: native) else { return nil }
            return UsageExample(sentence: sentence, translation: translation)
        }
    }

    static func otherMeanings(in content: GeneratedContent, excluding excluded: [String], native: LanguageCode) -> [String] {
        let items = (try? content.value([String].self, forProperty: "otherMeanings")) ?? []
        var seen = Set(excluded.map(normalized))
        var result: [String] = []
        for item in items.map(clean) where !item.isEmpty && wordCount(item) <= 8 && isPlausibly(item, in: native) {
            if seen.insert(normalized(item)).inserted {
                result.append(item)
            }
        }
        return Array(result.prefix(3))
    }

    // MARK: Checks

    private static func checkTranslation(_ translation: String, request: InsightRequest) throws(Failure) {
        let native = request.nativeLanguage.englishName
        guard !translation.isEmpty, wordCount(translation) <= 5 else {
            throw Failure(reason: "translation must be 1 to 4 \(native) words, not a sentence")
        }
        if let sentence = request.sentence, normalized(translation) == normalized(sentence) {
            throw Failure(reason: "translation must be the word, not the whole sentence")
        }
    }

    static func checkMeaning(_ meaning: String, native: LanguageCode) throws(Failure) {
        guard !meaning.isEmpty, wordCount(meaning) <= 30 else {
            throw Failure(reason: "meaning must be one short \(native.englishName) sentence")
        }
        guard isPlausibly(meaning, in: native) else {
            throw Failure(reason: "meaning must be written in \(native.englishName)")
        }
    }

    /// False only when the text is long enough to judge and confidently in another language.
    static func isPlausibly(_ text: String, in language: LanguageCode) -> Bool {
        guard wordCount(text) >= 4 else { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (detected, probability) = recognizer.languageHypotheses(withMaximum: 1).first,
              probability >= 0.8 else { return true }
        return LanguageCode(rawValue: detected.rawValue)?.languageSubtag == language.languageSubtag
    }

    private static func uses(term: String, lemma: String?, in sentence: String) -> Bool {
        let haystack = normalized(sentence)
        let needles = [term, lemma ?? ""].map(normalized).filter { !$0.isEmpty }
        if needles.contains(where: haystack.contains) { return true }
        // Inflected forms ("ran" for "run", "Banken" for "Bank") share a stem with the lemma.
        guard let stemSource = needles.last, stemSource.count >= 5 else { return false }
        return haystack.contains(String(stemSource.prefix(stemSource.count - 2)))
    }

    // MARK: Cleaning

    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotes: [(Character, Character)] = [("«", "»"), ("\"", "\""), ("“", "”"), ("'", "'"), ("„", "“")]
        for (open, close) in quotes where text.count >= 2 && text.first == open && text.last == close {
            text = String(text.dropFirst().dropLast())
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func cleanTranslation(_ raw: String) -> String {
        var text = clean(raw)
        while let last = text.last, ".;:!?,".contains(last) {
            text.removeLast()
        }
        return clean(text)
    }

    static func string(_ property: String, in content: GeneratedContent) -> String {
        (try? content.value(String.self, forProperty: property)) ?? ""
    }

    private static func partOfSpeech(in content: GeneratedContent) -> PartOfSpeech? {
        PartOfSpeech(rawValue: clean(string("partOfSpeech", in: content)).lowercased())
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
