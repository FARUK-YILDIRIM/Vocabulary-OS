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

    /// The words the script doesn't use, in the given order, in any form (see `WordOccurrences`).
    public static func missingWords(_ words: [QuizWord], in script: PodcastScript, language: LanguageCode) -> [QuizWord] {
        let used = Set(WordOccurrences.find(words, in: script.text, language: language).map(\.wordID))
        return words.filter { !used.contains($0.id) }
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
}
