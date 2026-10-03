import Foundation
import Testing
import VocabularyAI
import VocabularyCore
import VocabularyData
@testable import VocabularyUI

@Suite struct InboxCaptureDestinationTests {
    private let inbox = CaptureInbox(directory: FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)"))
    private let settings: SettingsStore

    init() throws {
        settings = SettingsStore(backing: InMemoryKeyValueBacking())
        settings.profile = try LearnerProfile(native: .turkish, learning: [.english, .german])
    }

    private func explainedModel() async -> CaptureModel {
        let model = CaptureModel(
            text: "This website uses cookies for tracking.",
            captureSource: .shareSheet,
            settings: settings,
            destination: InboxCaptureDestination(inbox: inbox)
        ) {
            InsightService(client: CannedClient(), strategy: .stepwise, source: InsightSource(providerID: "test"))
        }
        model.tap(tokenAt: 3)
        model.explain()
        await model.waitForExplanation()
        return model
    }

    @Test func savingWritesADraftForTheApp() async {
        let model = await explainedModel()
        model.save()

        #expect(model.phase == .saved)
        let drafts = inbox.pending()
        #expect(drafts.map(\.insight.term) == ["cookies"])
        #expect(drafts.first?.insight.translation == "çerez")
        #expect(drafts.first?.captureSource == .shareSheet)
    }

    @Test func warnsAboutAWordAlreadyWaitingInTheInbox() async {
        let first = await explainedModel()
        first.save()

        let second = await explainedModel()
        #expect(second.duplicateTranslation == "çerez")
    }
}
