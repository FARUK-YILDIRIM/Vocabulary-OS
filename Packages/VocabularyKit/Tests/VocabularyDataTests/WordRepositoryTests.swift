import Foundation
import SwiftData
import Testing
import VocabularyCore
@testable import VocabularyData

@Suite struct SchemaCloudKitRulesTests {
    @Test func theAppSchemaCanSyncWithCloudKit() {
        #expect(CloudKitSchemaRules.violations(in: VocabularyStore.schema) == [])
    }

    /// Proves the check catches real mistakes, so a passing app schema means something.
    @Test func catchesModelsThatCannotSync() {
        let problems = CloudKitSchemaRules.violations(in: Schema([UnsyncableNote.self, UnsyncableTag.self]))
        #expect(problems.contains("UnsyncableNote.title is unique"))
        #expect(problems.contains("UnsyncableNote.body needs a default value or must be optional"))
        #expect(problems.contains { $0.hasPrefix("UnsyncableTag.note") })
    }
}

@Model private final class UnsyncableNote {
    @Attribute(.unique) var title: String = ""
    var body: String
    init(body: String) { self.body = body }
}

@Model private final class UnsyncableTag {
    var note: UnsyncableNote
    init(note: UnsyncableNote) { self.note = note }
}

@MainActor
@Suite struct WordRepositoryTests {
    private let repository: WordRepository

    init() throws {
        repository = WordRepository(container: try VocabularyStore.makeContainer(inMemory: true, cloudSync: false))
    }

    private func insight(
        term: String = "cookies",
        lemma: String = "cookie",
        language: LanguageCode = .english,
        translation: String = "çerez"
    ) -> WordInsight {
        WordInsight(
            term: term, lemma: lemma, partOfSpeech: .noun, language: language, nativeLanguage: .turkish,
            context: "This website uses \(term) for tracking.", translation: translation,
            meaning: "Web sitelerinin sakladığı küçük veri dosyası.", englishGloss: "a small data file",
            grammarNote: nil, examples: [UsageExample(sentence: "Accept the cookies.", translation: "Çerezleri kabul et.")],
            otherMeanings: ["kurabiye"], source: InsightSource(providerID: "apple-on-device")
        )
    }

    @Test func savesAnInsightAndReadsItBack() throws {
        let entry = try repository.save(insight(), captureSource: .shareSheet)
        let stored = try #require(try repository.entries(language: .english).first)

        #expect(stored.id == entry.id)
        #expect(stored.insight == insight().withCreatedAt(stored.insight.createdAt))
        #expect(stored.captureSource == .shareSheet)
        #expect(stored.isNew)
        #expect(stored.cardState == CardState())
    }

    @Test func findsAnEntryByID() throws {
        let entry = try repository.save(insight(), captureSource: .text)
        #expect(try repository.entry(id: entry.id)?.term == "cookies")
        try repository.delete(entry)
        #expect(try repository.entry(id: entry.id) == nil)
        #expect(try repository.entry(id: UUID()) == nil)
    }

    @Test func findsDuplicatesByLemmaIgnoringCaseAndDiacritics() throws {
        try repository.save(insight(term: "Cookie", lemma: "Cookie"), captureSource: .text)
        #expect(try repository.existingEntry(lemma: "cookie", language: .english) != nil)
        #expect(try repository.existingEntry(lemma: "cookie", language: .german) == nil)
        try repository.save(insight(term: "Café", lemma: "Café", language: .german, translation: "kafe"), captureSource: .text)
        #expect(try repository.existingEntry(lemma: "cafe", language: .german) != nil)
    }

    @Test func separatesLanguages() throws {
        try repository.save(insight(), captureSource: .text)
        try repository.save(insight(term: "Bank", lemma: "Bank", language: .german, translation: "bank"), captureSource: .text)
        #expect(try repository.entries(language: .english).map(\.term) == ["cookies"])
        #expect(try repository.entries(language: .german).map(\.term) == ["Bank"])
        #expect(try repository.count(language: .german) == 1)
    }

    @Test func filtersFavoritesNewDueAndMastered() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = try repository.save(insight(term: "fresh", lemma: "fresh"), captureSource: .text)
        let due = try repository.save(insight(term: "due", lemma: "due"), captureSource: .text)
        due.cardState = CardState(ease: 2.5, intervalDays: 6, repetitions: 2, lapses: 0, dueAt: now.addingTimeInterval(-60), lastReviewedAt: now.addingTimeInterval(-6 * 86_400))
        let mastered = try repository.save(insight(term: "mastered", lemma: "mastered"), captureSource: .text)
        mastered.cardState = CardState(ease: 2.6, intervalDays: 30, repetitions: 5, lapses: 0, dueAt: now.addingTimeInterval(86_400 * 20), lastReviewedAt: now)
        mastered.isFavorite = true

        func terms(_ filter: LibraryFilter) throws -> Set<String> {
            Set(try repository.entries(language: .english, filter: filter, now: now).map(\.term))
        }
        #expect(try terms(.all) == ["fresh", "due", "mastered"])
        #expect(try terms(.new) == [fresh.term])
        #expect(try terms(.due) == ["due"])
        #expect(try terms(.mastered) == ["mastered"])
        #expect(try terms(.favorites) == ["mastered"])
    }

    @Test func searchesTermLemmaAndTranslation() throws {
        try repository.save(insight(), captureSource: .text)
        try repository.save(insight(term: "pitch", lemma: "pitch", translation: "sunum"), captureSource: .text)
        #expect(try repository.entries(language: .english, search: "SUN").map(\.term) == ["pitch"])
        #expect(try repository.entries(language: .english, search: "cookie").map(\.term) == ["cookies"])
    }

    @Test func sortsAlphabeticallyOrByRecency() throws {
        let first = try repository.save(insight(term: "zebra", lemma: "zebra"), captureSource: .text)
        first.createdAt = Date(timeIntervalSince1970: 1)
        try repository.save(insight(term: "apple", lemma: "apple"), captureSource: .text)
        #expect(try repository.entries(language: .english, sort: .alphabetical).map(\.term) == ["apple", "zebra"])
        #expect(try repository.entries(language: .english, sort: .recent).map(\.term) == ["apple", "zebra"])
        #expect(try repository.entries(language: .english, sort: .oldest).map(\.term) == ["zebra", "apple"])
    }

    @Test func listsKeepEntriesWhenDeletedAndForgetDeletedEntries() throws {
        let cookies = try repository.save(insight(), captureSource: .text)
        let pitch = try repository.save(insight(term: "pitch", lemma: "pitch", translation: "sunum"), captureSource: .text)
        let list = try repository.createList(named: "Web", language: .english)
        repository.add(cookies, to: list)
        repository.add(pitch, to: list)
        #expect(Set(list.entries?.map(\.term) ?? []) == ["cookies", "pitch"])

        try repository.delete(pitch)
        #expect(list.entries?.map(\.term) == ["cookies"])

        try repository.delete(list)
        #expect(try repository.entries(language: .english).map(\.term) == ["cookies"])
    }

    @Test func regeneratingAnInsightKeepsTheReviewState() throws {
        let entry = try repository.save(insight(), captureSource: .text)
        let reviewed = CardState(ease: 2.36, intervalDays: 6, repetitions: 2, lapses: 0, dueAt: .distantFuture, lastReviewedAt: Date())
        entry.cardState = reviewed
        try repository.update(entry, with: insight(translation: "tanımlama bilgisi"))

        #expect(entry.translation == "tanımlama bilgisi")
        #expect(entry.cardState == reviewed)
    }
}

private extension WordInsight {
    func withCreatedAt(_ date: Date) -> WordInsight {
        var copy = self
        copy.createdAt = date
        return copy
    }
}
