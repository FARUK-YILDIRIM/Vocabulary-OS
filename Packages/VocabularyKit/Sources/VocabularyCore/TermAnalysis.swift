import Foundation
import NaturalLanguage

public enum PartOfSpeech: String, Codable, Sendable, CaseIterable {
    case noun, verb, adjective, adverb, pronoun, preposition, conjunction, interjection
    case determiner, number, phrase, other
}

/// On-device lemma and part of speech for a selected term (ADR-004).
///
/// Uses NaturalLanguage where the language supports the tag scheme (English, Turkish, Spanish, French,
/// and others) and returns `nil` where it doesn't (German on macOS 26). In that case the AI model
/// supplies the lemma.
public struct TermAnalysis: Hashable, Sendable {
    public var lemma: String?
    public var partOfSpeech: PartOfSpeech?

    public init(lemma: String? = nil, partOfSpeech: PartOfSpeech? = nil) {
        self.lemma = lemma
        self.partOfSpeech = partOfSpeech
    }

    public static func analyze(term: String, in sentence: String?, language: LanguageCode) -> TermAnalysis {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return TermAnalysis() }
        if TokenizedText(term).tokens.count > 1 {
            return TermAnalysis(partOfSpeech: .phrase)
        }

        // Tag the term inside its sentence when possible: lexical class depends on context.
        let context = sentence ?? term
        let termRange = context.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
            ?? context.startIndex..<context.endIndex
        let nlLanguage = NLLanguage(rawValue: language.languageSubtag)
        let available = NLTagger.availableTagSchemes(for: .word, language: nlLanguage)

        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = context
        tagger.setLanguage(nlLanguage, range: context.startIndex..<context.endIndex)

        var result = TermAnalysis()
        if available.contains(.lemma),
           let lemma = tagger.tag(at: termRange.lowerBound, unit: .word, scheme: .lemma).0?.rawValue,
           !lemma.isEmpty {
            result.lemma = lemma
        }
        if available.contains(.lexicalClass),
           let tag = tagger.tag(at: termRange.lowerBound, unit: .word, scheme: .lexicalClass).0 {
            result.partOfSpeech = PartOfSpeech(lexicalClass: tag)
        }
        return result
    }
}

extension PartOfSpeech {
    init?(lexicalClass tag: NLTag) {
        switch tag {
        case .noun: self = .noun
        case .verb: self = .verb
        case .adjective: self = .adjective
        case .adverb: self = .adverb
        case .pronoun: self = .pronoun
        case .preposition: self = .preposition
        case .conjunction: self = .conjunction
        case .interjection: self = .interjection
        case .determiner: self = .determiner
        case .number: self = .number
        case .idiom: self = .phrase
        case .otherWord, .particle, .classifier: self = .other
        default: return nil
        }
    }
}
