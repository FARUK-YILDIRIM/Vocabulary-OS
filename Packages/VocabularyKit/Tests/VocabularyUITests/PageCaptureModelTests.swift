import Foundation
import Testing
import VocabularyAI
import VocabularyCapture
import VocabularyCore
import VocabularyData
@testable import VocabularyUI

@Suite struct PageCaptureModelTests {
    private let settings: SettingsStore
    private let destination = PhotoRecordingDestination()

    init() throws {
        settings = SettingsStore(backing: InMemoryKeyValueBacking())
        settings.profile = try LearnerProfile(native: .turkish, learning: [.english, .german])
    }

    private func makeModel() -> PageCaptureModel {
        PageCaptureModel(settings: settings, destination: { [destination] photo in
            destination.photo = photo
            return destination
        }) {
            InsightService(client: CannedClient(), strategy: .stepwise, source: InsightSource(providerID: "test"))
        }
    }

    @Test func tappingAWordOpensCaptureWithItsSentence() async throws {
        let model = makeModel()
        await model.load(PageImages.jpeg())

        #expect(model.phase == .recognized)
        #expect(model.displayImage != nil)
        let banks = try #require(model.page?.words.filter { $0.text == "Bank" })
        try #require(banks.count == 2)

        model.tap(banks[1])
        let capture = try #require(model.capture)
        #expect(capture.text == "Danach treffe ich meine Freundin im Park, wo wir auf einer alten Bank sitzen und reden.")
        #expect(capture.term == "Bank")
        #expect(capture.language == .german)
        #expect(capture.captureSource == .page)
        #expect(model.tappedWord == banks[1])
    }

    @Test func savedWordsKeepASmallCopyOfThePhotoUnlessTurnedOff() async throws {
        let model = makeModel()
        await model.load(PageImages.jpeg())
        let ran = try #require(model.page?.words.first { $0.text == "ran" })

        model.tap(ran)
        #expect(destination.photo != nil)

        model.savesPhoto = false
        model.tap(ran)
        #expect(destination.photo == nil)
    }

    @Test func dataThatIsNotAnImageFails() async {
        let model = makeModel()
        await model.load(Data("not an image".utf8))
        #expect(model.phase == .failed(.unreadableImage))
        #expect(model.page == nil)
    }

    /// SwiftUI cancels a view's task when the view goes away, which is not a failure to report.
    @Test func aCancelledLoadLeavesThePageEmpty() async {
        let model = makeModel()
        let load = Task { await model.load(PageImages.jpeg()) }
        load.cancel()
        await load.value

        #expect(model.phase == .empty)
        #expect(model.displayImage == nil)
    }

    @Test func resettingGoesBackToChoosingAPhoto() async {
        let model = makeModel()
        await model.load(PageImages.jpeg())
        model.reset()
        #expect(model.phase == .empty)
        #expect(model.displayImage == nil)
    }
}

/// Records the photo handed to the destination for the last tapped word.
private final class PhotoRecordingDestination: CaptureDestination {
    var photo: Data?

    func savedTranslation(lemma: String, language: LanguageCode) -> String? { nil }
    func save(_ insight: WordInsight, captureSource: CaptureSource) throws {}
}
