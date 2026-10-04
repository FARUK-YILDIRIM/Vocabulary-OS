import Foundation
import NaturalLanguage

/// Where saved words occur in a text, in any form (SPEC C9): as written, inflected ("Banken" for
/// "Bank"), or through its dictionary form where NaturalLanguage knows the language ("ran" for
/// "run"). Podcast validation and the transcript's word links share it, so every word the validator
/// counts as used is highlighted.
public enum WordOccurrences {
    public struct Match: Hashable, Sendable {
        public let wordID: UUID
        public let range: Range<String.Index>
    }

    /// Every occurrence in reading order; a phrase and a word inside it can overlap.
    public static func find(_ words: [QuizWord], in text: String, language: LanguageCode) -> [Match] {
        let tokens = TokenizedText(text).tokens
        let lemmas = lemmas(of: tokens, in: text, language: language)
        var matches: [Match] = []
        for word in words {
            if word.term.contains(" ") {
                var searched = text.startIndex..<text.endIndex
                while let range = text.range(of: word.term, options: [.caseInsensitive, .diacriticInsensitive], range: searched) {
                    matches.append(Match(wordID: word.id, range: range))
                    searched = range.upperBound..<text.endIndex
                }
            } else {
                let forms = Set([word.term.matchingKey, word.lemma.matchingKey])
                for (token, lemma) in zip(tokens, lemmas) where isForm(token.text, of: word) || lemma.map(forms.contains) == true {
                    matches.append(Match(wordID: word.id, range: token.range))
                }
            }
        }
        return matches.sorted { lhs, rhs in
            lhs.range.lowerBound != rhs.range.lowerBound
                ? lhs.range.lowerBound < rhs.range.lowerBound
                : lhs.range.upperBound > rhs.range.upperBound
        }
    }

    /// Occurrences to highlight: where two overlap, the one that starts first, or the longer, wins.
    public static func highlights(_ words: [QuizWord], in text: String, language: LanguageCode) -> [Match] {
        var highlights: [Match] = []
        for match in find(words, in: text, language: language)
        where highlights.last.map({ $0.range.upperBound <= match.range.lowerBound }) ?? true {
            highlights.append(match)
        }
        return highlights
    }

    /// The text as written or inflected. A word under four letters allows only two more letters: its
    /// prefix also starts unrelated words ("ran" in "random"), and its longer inflections come through
    /// the dictionary form. Quiz checks keep the wider rule, where matching too much is the safe side.
    static func isForm(_ text: String, of word: QuizWord) -> Bool {
        [word.term, word.lemma].contains { form in
            let key = form.matchingKey
            guard key.count < 4 else { return QuizValidator.isForm(text, ofText: form) }
            let candidate = text.matchingKey
            return !key.isEmpty && candidate.hasPrefix(key) && candidate.count <= key.count + 2
        }
    }

    /// The dictionary form of each token, or `nil` where the language has no lemmatizer.
    private static func lemmas(of tokens: [TextToken], in text: String, language: LanguageCode) -> [String?] {
        let nlLanguage = NLLanguage(rawValue: language.languageSubtag)
        guard NLTagger.availableTagSchemes(for: .word, language: nlLanguage).contains(.lemma) else {
            return tokens.map { _ in nil }
        }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.setLanguage(nlLanguage, range: text.startIndex..<text.endIndex)
        return tokens.map { token in
            tagger.tag(at: token.range.lowerBound, unit: .word, scheme: .lemma).0.map(\.rawValue.matchingKey)
        }
    }
}
