import Foundation
import NaturalLanguage

/// Checks a podcast script before it is saved (SPEC C9, ADR-008): a title, non-empty segments with
/// the right speakers, a capped length, and every chosen word, in any inflected form.
public enum PodcastValidator {
    public enum Problem: Error, Equatable, Sendable {
        case missingTitle
        case noSegments
        case emptySegment
        /// A dialogue needs both hosts and no narrator; a story only the narrator.
        case wrongSpeakers
        case tooLong
        /// A sentence appears twice: small models sometimes loop.
        case repeatedSentence
        /// The chosen words the script doesn't use.
        case missingWords([String])
    }

    public static func validate(
        _ script: PodcastScript,
        words: [QuizWord],
        language: LanguageCode,
        style: PodcastStyle,
        length: PodcastLength
    ) throws(Problem) {
        guard !script.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .missingTitle }
        guard !script.segments.isEmpty else { throw .noSegments }
        guard script.segments.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw .emptySegment
        }
        let speakers = Set(script.segments.map(\.speaker))
        switch style {
        case .dialogue:
            guard speakers == [.host, .guest] else { throw .wrongSpeakers }
        case .story:
            guard speakers == [.narrator] else { throw .wrongSpeakers }
        }
        guard script.wordCount <= length.maximumWords else { throw .tooLong }
        guard !repeatsASentence(script.segments) else { throw .repeatedSentence }
        let missing = missingWords(words, in: script, language: language)
        guard missing.isEmpty else { throw .missingWords(missing.map(\.term)) }
    }

    /// The words the script doesn't use, in the given order. A word counts as used in any form: as
    /// written, inflected ("Banken" for "Bank"), or through its dictionary form where NaturalLanguage
    /// knows the language ("ran" for "run").
    public static func missingWords(_ words: [QuizWord], in script: PodcastScript, language: LanguageCode) -> [QuizWord] {
        let text = script.text
        let tokens = TokenizedText(text).tokens
        let lemmas = Self.lemmas(of: text, language: language)
        return words.filter { word in
            if word.term.contains(" ") {
                return text.range(of: word.term, options: [.caseInsensitive, .diacriticInsensitive]) == nil
            }
            let forms = Set([word.term.matchingKey, word.lemma.matchingKey])
            let used = tokens.contains { QuizValidator.isForm($0.text, of: word) } || !forms.isDisjoint(with: lemmas)
            return !used
        }
    }

    /// Whether any sentence appears twice, ignoring case, accents and spacing.
    public static func repeatsASentence(_ segments: [PodcastSegment]) -> Bool {
        removingRepeatedSentences(from: segments, after: []) != segments
    }

    /// The segments without sentences already said, in them or in `earlier`; segments left empty are
    /// dropped. Short replies such as "Ja." may come back naturally and are kept.
    public static func removingRepeatedSentences(from segments: [PodcastSegment], after earlier: [PodcastSegment]) -> [PodcastSegment] {
        var seen: Set<String> = []
        for segment in earlier {
            for sentence in sentences(of: segment.text) where sentence.key.count > 12 {
                seen.insert(sentence.key)
            }
        }
        var result: [PodcastSegment] = []
        for segment in segments {
            var kept: [String] = []
            var changed = false
            for sentence in sentences(of: segment.text) {
                if sentence.key.count > 12, !seen.insert(sentence.key).inserted {
                    changed = true
                } else {
                    kept.append(sentence.text)
                }
            }
            guard changed else {
                result.append(segment)
                continue
            }
            if !kept.isEmpty {
                result.append(PodcastSegment(speaker: segment.speaker, text: kept.joined(separator: " ")))
            }
        }
        return result
    }

    private static func sentences(of text: String) -> [(text: String, key: String)] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [(text: String, key: String)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !sentence.isEmpty {
                sentences.append((sentence, sentence.matchingKey))
            }
            return true
        }
        return sentences
    }

    /// Dictionary forms of the text's words, empty where the language has no lemmatizer.
    private static func lemmas(of text: String, language: LanguageCode) -> Set<String> {
        let nlLanguage = NLLanguage(rawValue: language.languageSubtag)
        guard NLTagger.availableTagSchemes(for: .word, language: nlLanguage).contains(.lemma) else { return [] }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.setLanguage(nlLanguage, range: text.startIndex..<text.endIndex)
        var lemmas: Set<String> = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma, options: [.omitPunctuation, .omitWhitespace]) { tag, _ in
            if let lemma = tag?.rawValue, !lemma.isEmpty {
                lemmas.insert(lemma.matchingKey)
            }
            return true
        }
        return lemmas
    }
}
