import Foundation
import SwiftData
import Testing
import VocabularyCore
@testable import VocabularyData

@MainActor
@Suite struct ExportImportTests {
    private let library: WordRepository
    private let friend: WordRepository

    init() throws {
        library = WordRepository(container: try VocabularyStore.makeContainer(inMemory: true, cloudSync: false))
        friend = WordRepository(container: try VocabularyStore.makeContainer(inMemory: true, cloudSync: false))
    }

    private func insight(_ term: String, lemma: String? = nil, translation: String = "çeviri") -> WordInsight {
        WordInsight(
            term: term, lemma: lemma ?? term, partOfSpeech: .noun, language: .german, nativeLanguage: .turkish,
            context: "Wir treffen uns am \(term).", translation: translation, meaning: "Anlam, \"tırnaklı\".",
            englishGloss: "a gloss", grammarNote: "der \(term), die \(term)e",
            examples: [UsageExample(sentence: "Der \(term) ist neu.", translation: "Yeni.")],
            otherMeanings: ["başka"], source: InsightSource(providerID: "openai", modelID: "gpt-5-mini"),
            createdAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
    }

    /// Three German words; Bahnhof and Fahrkarte are in the list "Reisen".
    private func makeTravelList() throws -> WordList {
        let station = try library.save(insight("Bahnhof", translation: "istasyon"), captureSource: .text)
        let ticket = try library.save(insight("Fahrkarten", lemma: "Fahrkarte", translation: "bilet"), captureSource: .page)
        _ = try library.save(insight("Bank", translation: "bank"), captureSource: .text)
        let list = try library.createList(named: "Reisen", language: .german)
        library.add(station, to: list)
        library.add(ticket, to: list)
        try library.context.save()
        return list
    }

    @Test func aListRoundTripsWithoutLoss() throws {
        let list = try makeTravelList()
        let data = try library.document(for: list).data()
        let document = try WordListDocument.read(data)
        #expect(document.name == "Reisen")
        #expect(document.language == .german)

        let result = try friend.importWords(from: document)
        #expect(result == WordListImport(newWords: 2, existingWords: 0))
        let imported = try friend.entries(language: .german, sort: .alphabetical)
        let original = try library.entries(language: .german, sort: .alphabetical).filter { $0.lists?.isEmpty == false }
        #expect(imported.map(\.insight) == original.map(\.insight))
        #expect(imported.allSatisfy { $0.captureSource == .imported })
        let lists = try friend.context.fetch(FetchDescriptor<WordList>())
        #expect(lists.map(\.name) == ["Reisen"])
        #expect(Set(lists.first?.entries?.map(\.term) ?? []) == ["Bahnhof", "Fahrkarten"])
    }

    @Test func aLanguageExportsAllItsWords() throws {
        _ = try makeTravelList()
        let document = try library.document(language: .german)
        #expect(document.name == nil)
        #expect(document.words.map(\.term).sorted() == ["Bahnhof", "Bank", "Fahrkarten"])
        #expect(try library.document(language: .english).words.isEmpty)
    }

    @Test func importingTwiceAddsNothing() throws {
        let document = library.document(for: try makeTravelList())
        try friend.importWords(from: document)
        #expect(try friend.preview(document) == WordListImport(newWords: 0, existingWords: 2))

        #expect(try friend.importWords(from: document) == WordListImport(newWords: 0, existingWords: 2))
        #expect(try friend.count(language: .german) == 2)
        let lists = try friend.context.fetch(FetchDescriptor<WordList>())
        #expect(lists.count == 1)
        #expect(lists.first?.entries?.count == 2)
    }

    /// A word the library already has is kept as it is, and still joins the imported list.
    @Test func keepsSavedWordsAndListsThem() throws {
        let document = library.document(for: try makeTravelList())
        let saved = try friend.save(insight("bahnhof", lemma: "Bahnhof", translation: "gar"), captureSource: .text)
        saved.isFavorite = true

        #expect(try friend.preview(document) == WordListImport(newWords: 1, existingWords: 1))
        #expect(try friend.importWords(from: document) == WordListImport(newWords: 1, existingWords: 1))
        #expect(saved.translation == "gar")
        #expect(saved.isFavorite)
        #expect(saved.lists?.map(\.name) == ["Reisen"])
    }

    /// Only the words' explanations travel: no review state or history, photos, favorites, lists
    /// of other words, or keys.
    @Test func exportsOnlyTheExplanations() throws {
        let list = try makeTravelList()
        for entry in try library.entries(language: .german) {
            entry.isFavorite = true
            entry.imageData = Data([0xFF, 0xD8, 0xFF])
            entry.cardState = CardState(ease: 2.2, intervalDays: 12, repetitions: 4, dueAt: .now, lastReviewedAt: .now)
        }
        try library.context.save()

        let json = try #require(try JSONSerialization.jsonObject(with: library.document(for: list).data()) as? [String: Any])
        #expect(Set(json.keys) == ["format", "version", "exportedAt", "name", "language", "words"])
        let words = try #require(json["words"] as? [[String: Any]])
        #expect(words.count == 2)
        let allowed: Set<String> = [
            "term", "lemma", "partOfSpeech", "language", "nativeLanguage", "context", "translation", "meaning",
            "englishGloss", "grammarNote", "examples", "otherMeanings", "source", "explainedAt",
        ]
        #expect(words.allSatisfy { Set($0.keys).isSubset(of: allowed) })
    }

    @Test func refusesOtherFiles() throws {
        let document = library.document(for: try makeTravelList())
        var newer = document
        newer.version = WordListDocument.currentVersion + 1
        #expect(throws: WordListDocument.ReadError.newerVersion) { try WordListDocument.read(try newer.data()) }
        var other = document
        other.format = "something.else"
        #expect(throws: WordListDocument.ReadError.notAWordList) { try WordListDocument.read(try other.data()) }
        #expect(throws: WordListDocument.ReadError.notAWordList) { try WordListDocument.read(Data("{\"words\": 3}".utf8)) }
        #expect(throws: WordListDocument.ReadError.notAWordList) { try WordListDocument.read(Data("not json".utf8)) }
    }

    /// A file is checked for its size before it is read, so a huge one can't freeze the app.
    @Test func refusesAFileTooLargeToOpenBeforeReadingIt() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "list-\(UUID().uuidString).vocabularyos")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try library.document(for: try makeTravelList()).data()
        try data.write(to: url)

        #expect(try WordListDocument.read(contentsOf: url).words.count == 2)
        #expect(throws: WordListDocument.ReadError.tooLarge) {
            try WordListDocument.read(contentsOf: url, maximumSize: data.count - 1)
        }
    }

    @Test func writesCSVForSpreadsheets() throws {
        let document = library.document(for: try makeTravelList())
        let csv = CSVExporter.csv(for: document.words)
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines.first == "term,lemma,part_of_speech,translation,meaning,sentence,example,example_translation,language,native_language")
        #expect(lines.count == 4, "A header, two words and the final line break")
        #expect(lines.last == "")
        // Fields with commas or quotes are quoted, and quotes are doubled.
        #expect(lines.contains { $0.contains("\"Anlam, \"\"tırnaklı\"\".\"") })
        #expect(CSVExporter.field("one\ntwo") == "\"one\ntwo\"")
        #expect(CSVExporter.field("plain") == "plain")
    }

    /// Words can come from shared lists and web pages; a spreadsheet must show them, not run them.
    @Test(arguments: [
        ("=HYPERLINK(\"https://example.com\",\"Audio\")", "\"'=HYPERLINK(\"\"https://example.com\"\",\"\"Audio\"\")\""),
        ("+1 to remember", "'+1 to remember"),
        ("-ish", "'-ish"),
        ("@SUM(A1)", "'@SUM(A1)"),
        ("\tTab", "'\tTab"),
        ("\rReturn", "\"'\rReturn\""),
        ("＝HYPERLINK()", "'＝HYPERLINK()"),
        ("e-mail", "e-mail"),
    ])
    func keepsSpreadsheetsFromRunningFormulas(_ value: String, _ expected: String) {
        #expect(CSVExporter.field(value) == expected)
    }
}
