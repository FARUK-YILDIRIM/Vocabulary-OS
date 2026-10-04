import Foundation
import SwiftData
import Testing
import VocabularyCore
@testable import VocabularyData

/// The store has no versioned schema: CloudKit allows only additive changes after release, and
/// SwiftData migrates those on its own (ADR-002, code review). These tests open stores on disk the
/// way an update would.
@Suite struct StoreMigrationTests {
    private let url = FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString).sqlite")

    @MainActor
    @Test func theLibraryOpensAgainWithItsWords() throws {
        do {
            let repository = WordRepository(container: try VocabularyStore.makeContainer(url: url, cloudSync: false))
            try repository.save(.sample, captureSource: .text)
        }
        let reopened = WordRepository(container: try VocabularyStore.makeContainer(url: url, cloudSync: false))
        #expect(try reopened.entries(language: .english).map(\.term) == ["cookies"])
    }

    /// What a release after v1 may do: add a property with a default, or an optional one.
    @Test func anAddedPropertyNeedsNoMigrationPlan() throws {
        do {
            let container = try ModelContainer(for: Before.Note.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            context.insert(Before.Note(text: "kept"))
            try context.save()
        }
        let container = try ModelContainer(for: After.Note.self, configurations: ModelConfiguration(url: url))
        let notes = try ModelContext(container).fetch(FetchDescriptor<After.Note>())
        #expect(notes.map(\.text) == ["kept"])
        #expect(notes.first?.isPinned == false)
        #expect(notes.first?.color == nil)
    }

    enum Before {
        @Model final class Note {
            var text: String = ""
            init(text: String) { self.text = text }
        }
    }

    enum After {
        @Model final class Note {
            var text: String = ""
            var isPinned: Bool = false
            var color: String?
            init(text: String) { self.text = text }
        }
    }
}

private extension WordInsight {
    static let sample = WordInsight(
        term: "cookies", lemma: "cookie", language: .english, nativeLanguage: .turkish,
        translation: "çerez", meaning: "Küçük veri dosyası.", source: InsightSource(providerID: "apple-on-device")
    )
}
