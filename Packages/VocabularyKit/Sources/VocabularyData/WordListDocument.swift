import Foundation
import SwiftData
import VocabularyCore

/// A word list as a file (SPEC C11, ADR-002): versioned JSON with the words' explanations. Review
/// state and history, photos, favorites and API keys never leave the device this way.
public struct WordListDocument: Codable, Hashable, Sendable {
    /// Marks the file as a word list, so other JSON isn't taken for one.
    public static let formatName = "vocabularyos.wordlist"
    /// The version this app writes. Files from a newer version are refused rather than half read.
    public static let currentVersion = 1
    public static let fileExtension = "vocabularyos"

    public var format: String
    public var version: Int
    public var exportedAt: Date
    /// The list's name; `nil` for all words of a language.
    public var name: String?
    public var language: LanguageCode
    public var words: [Word]

    /// A word's explanation, field by field, so the file format doesn't change with the app's models.
    public struct Word: Codable, Hashable, Sendable {
        public var term: String
        public var lemma: String
        public var partOfSpeech: PartOfSpeech?
        public var language: LanguageCode
        public var nativeLanguage: LanguageCode
        public var context: String?
        public var translation: String
        public var meaning: String
        public var englishGloss: String?
        public var grammarNote: String?
        public var examples: [UsageExample]
        public var otherMeanings: [String]
        public var source: InsightSource
        public var explainedAt: Date

        public init(_ insight: WordInsight) {
            term = insight.term
            lemma = insight.lemma
            partOfSpeech = insight.partOfSpeech
            language = insight.language
            nativeLanguage = insight.nativeLanguage
            context = insight.context
            translation = insight.translation
            meaning = insight.meaning
            englishGloss = insight.englishGloss
            grammarNote = insight.grammarNote
            examples = insight.examples
            otherMeanings = insight.otherMeanings
            source = insight.source
            explainedAt = insight.createdAt
        }

        public var insight: WordInsight {
            WordInsight(
                term: term, lemma: lemma, partOfSpeech: partOfSpeech, language: language, nativeLanguage: nativeLanguage,
                context: context, translation: translation, meaning: meaning, englishGloss: englishGloss,
                grammarNote: grammarNote, examples: examples, otherMeanings: otherMeanings, source: source,
                createdAt: explainedAt
            )
        }
    }

    public enum ReadError: Error, Hashable, Sendable {
        /// Not JSON, or JSON that isn't a word list.
        case notAWordList
        /// Written by a newer version of the app.
        case newerVersion
    }

    public init(name: String?, language: LanguageCode, words: [Word], exportedAt: Date = .now) {
        self.format = Self.formatName
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.name = name
        self.language = language
        self.words = words
    }

    /// Reads a file, checking what it is before reading the words.
    public static func read(_ data: Data) throws(ReadError) -> WordListDocument {
        struct Header: Decodable {
            var format: String
            var version: Int
        }
        let decoder = Self.decoder
        guard let header = try? decoder.decode(Header.self, from: data), header.format == formatName else {
            throw .notAWordList
        }
        guard header.version <= currentVersion else { throw .newerVersion }
        guard let document = try? decoder.decode(WordListDocument.self, from: data) else { throw .notAWordList }
        return document
    }

    /// The file's contents: readable JSON with ISO 8601 dates.
    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// What an import adds (SPEC C11).
public struct WordListImport: Hashable, Sendable {
    /// Words the library didn't have.
    public var newWords: Int
    /// Words already saved with the same dictionary form and language; they stay as they are.
    public var existingWords: Int

    public init(newWords: Int, existingWords: Int) {
        self.newWords = newWords
        self.existingWords = existingWords
    }
}

extension WordRepository {
    /// A list's words as a file.
    public func document(for list: WordList) -> WordListDocument {
        let entries = (list.entries ?? []).sorted { $0.createdAt < $1.createdAt }
        return WordListDocument(name: list.name, language: list.language ?? .english, words: entries.map { .init($0.insight) })
    }

    /// All words of a language as a file.
    public func document(language: LanguageCode) throws -> WordListDocument {
        WordListDocument(name: nil, language: language, words: try entries(language: language, sort: .oldest).map { .init($0.insight) })
    }

    /// What importing the file would add, for the learner to confirm.
    public func preview(_ document: WordListDocument) throws -> WordListImport {
        var seen: Set<String> = []
        var result = WordListImport(newWords: 0, existingWords: 0)
        for word in document.words {
            let key = "\(word.language.rawValue)|\(word.lemma.matchingKey)"
            guard seen.insert(key).inserted else { continue }
            if try existingEntry(lemma: word.lemma, language: word.language) == nil {
                result.newWords += 1
            } else {
                result.existingWords += 1
            }
        }
        return result
    }

    /// Adds the file's words the library doesn't have; saved words stay as they are. A named list is
    /// created, or reused when the language already has one with that name, and gets all its words.
    @discardableResult
    public func importWords(from document: WordListDocument) throws -> WordListImport {
        let target = try document.name.map { try list(named: $0, language: document.language) }
        var result = WordListImport(newWords: 0, existingWords: 0)
        var handled: Set<PersistentIdentifier> = []
        for word in document.words {
            let entry: VocabularyEntry
            if let existing = try existingEntry(lemma: word.lemma, language: word.language) {
                entry = existing
                if handled.contains(existing.persistentModelID) { continue }
                result.existingWords += 1
            } else {
                entry = try save(word.insight, captureSource: .imported)
                result.newWords += 1
            }
            handled.insert(entry.persistentModelID)
            if let target, entry.language == target.language, !(entry.lists ?? []).contains(where: { $0.id == target.id }) {
                add(entry, to: target)
            }
        }
        try context.save()
        return result
    }

    /// The language's list with this name, or a new one.
    private func list(named name: String, language: LanguageCode) throws -> WordList {
        let code = language.rawValue
        let lists = try context.fetch(FetchDescriptor<WordList>(predicate: #Predicate { $0.languageCode == code }))
        if let existing = lists.first(where: { $0.name.matchingKey == name.matchingKey }) {
            return existing
        }
        return try createList(named: name, language: language)
    }
}

/// Words as CSV for spreadsheets and Anki (SPEC C11): RFC 4180, UTF-8, one row per word.
public enum CSVExporter {
    public static let columns = [
        "term", "lemma", "part_of_speech", "translation", "meaning", "sentence", "example", "example_translation",
        "language", "native_language",
    ]

    public static func csv(for words: [WordListDocument.Word]) -> String {
        var rows = [columns]
        for word in words {
            let example = word.examples.first
            rows.append([
                word.term, word.lemma, word.partOfSpeech?.rawValue ?? "", word.translation, word.meaning,
                word.context ?? "", example?.sentence ?? "", example?.translation ?? "",
                word.language.rawValue, word.nativeLanguage.rawValue,
            ])
        }
        return rows.map { $0.map(field).joined(separator: ",") + "\r\n" }.joined()
    }

    /// The value quoted when it has a comma, quote or line break; quotes inside are doubled.
    public static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
