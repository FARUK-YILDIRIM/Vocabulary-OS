import Foundation
import Testing
import VocabularyCore
@testable import VocabularyData

@Suite struct CaptureInboxTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")
    private var inbox: CaptureInbox { CaptureInbox(directory: directory) }

    private func draft(_ term: String = "cookies") -> CaptureDraft {
        CaptureDraft(
            insight: WordInsight(term: term, lemma: term, language: .english, nativeLanguage: .turkish,
                                 translation: "çerez", meaning: "Küçük veri dosyası.", source: InsightSource(providerID: "apple-on-device")),
            captureSource: .shareSheet
        )
    }

    @Test func writesAndReadsDraftsInOrder() throws {
        let first = draft("first")
        try inbox.write(first)
        let second = draft("second")
        try inbox.write(second)

        #expect(inbox.pending().map(\.insight.term) == ["first", "second"])
        #expect(inbox.pending().first == first)
    }

    @Test func removesImportedDrafts() throws {
        let item = draft()
        try inbox.write(item)
        try inbox.remove(item.id)
        #expect(inbox.pending().isEmpty)
    }

    /// A draft this version can't read, perhaps written by a newer extension, is kept aside for a
    /// later version rather than deleted.
    @Test func setsUnreadableFilesAsideInsteadOfDeletingThem() throws {
        try inbox.write(draft())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "broken.json"))

        #expect(inbox.pending().map(\.insight.term) == ["cookies"])
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "broken.json").path()))
        let kept = directory.appending(path: CaptureInbox.unreadableFolder).appending(path: "broken.json")
        #expect(try Data(contentsOf: kept) == Data("not json".utf8))
        #expect(inbox.pending().map(\.insight.term) == ["cookies"], "files set aside aren't read again")
    }

    @Test func anEmptyOrMissingInboxHasNothingPending() {
        #expect(inbox.pending().isEmpty)
    }

    @MainActor
    @Test func importingMovesDraftsIntoTheLibrary() throws {
        let repository = WordRepository(container: try VocabularyStore.makeContainer(inMemory: true, cloudSync: false))
        try inbox.write(draft("cookies"))
        try inbox.write(draft("pitch"))

        let count = CaptureInbox.importPending(from: inbox, into: repository)

        #expect(count == 2)
        #expect(Set(try repository.entries(language: .english).map(\.term)) == ["cookies", "pitch"])
        #expect(try repository.entries(language: .english).allSatisfy { $0.captureSource == .shareSheet })
        #expect(inbox.pending().isEmpty)
        #expect(CaptureInbox.importPending(from: inbox, into: repository) == 0)
    }

    /// The extension can't see the library, so the import keeps a word the learner already has from
    /// being saved twice (SPEC C4).
    @MainActor
    @Test func aWordAlreadyInTheLibraryIsNotImportedAgain() throws {
        let repository = WordRepository(container: try VocabularyStore.makeContainer(inMemory: true, cloudSync: false))
        try repository.save(draft("cookies").insight, captureSource: .text)
        try inbox.write(draft("cookies"))
        try inbox.write(draft("pitch"))

        #expect(CaptureInbox.importPending(from: inbox, into: repository) == 1)
        #expect(try repository.entries(language: .english).map(\.term).sorted() == ["cookies", "pitch"])
        #expect(inbox.pending().isEmpty, "the duplicate's draft is done with too")
    }
}
