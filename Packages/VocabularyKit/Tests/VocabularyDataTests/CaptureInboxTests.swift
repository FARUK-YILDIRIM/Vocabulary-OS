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

    @Test func setsCorruptFilesAsideInsteadOfFailing() throws {
        try inbox.write(draft())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "broken.json"))

        #expect(inbox.pending().map(\.insight.term) == ["cookies"])
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "broken.json").path()))
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
}
