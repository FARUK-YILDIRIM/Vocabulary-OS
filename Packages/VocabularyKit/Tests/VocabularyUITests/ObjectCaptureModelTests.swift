#if canImport(AppKit)
import Foundation
import FoundationModels
import Synchronization
import Testing
import VocabularyAI
import VocabularyCapture
import VocabularyCore
import VocabularyData
@testable import VocabularyUI

@Suite struct ObjectCaptureModelTests {
    private let settings: SettingsStore
    private let destination = SavingDestination()

    init() throws {
        settings = SettingsStore(backing: InMemoryKeyValueBacking())
        settings.profile = try LearnerProfile(native: .turkish, learning: [.english, .german])
    }

    private func makeModel(client: any GenerationClient = TasseClient(), sharesPhoto: Bool = false) -> ObjectCaptureModel {
        ObjectCaptureModel(
            settings: settings,
            destination: { [destination] photo in
                destination.photo = photo
                return destination
            },
            sharesPhoto: { sharesPhoto }
        ) {
            InsightService(client: client, strategy: .stepwise, source: InsightSource(providerID: "test"))
        }
    }

    @Test func aPhotoOffersItsLabelsAndTheFirstLearningLanguage() async {
        let model = makeModel()
        await model.load(ObjectImages.jpeg())

        #expect(model.phase == .choosing)
        #expect(model.labels.first?.identifier == "cup")
        #expect(model.label == "cup")
        #expect(model.language == .english)
        #expect(model.canName)
    }

    @Test func namingAndSavingKeepsThePhoto() async throws {
        let model = makeModel()
        await model.load(ObjectImages.jpeg())
        model.language = .german
        model.name()
        await model.waitForName()

        #expect(model.phase == .named)
        #expect(model.insight?.term == "die Tasse")
        model.save()
        #expect(model.phase == .saved)
        #expect(destination.saved.map(\.term) == ["die Tasse"])
        #expect(destination.source == .object)
        #expect(destination.photo != nil)
    }

    @Test func changingTheLabelDiscardsTheName() async {
        let model = makeModel()
        await model.load(ObjectImages.jpeg())
        model.name()
        await model.waitForName()

        model.label = "mug"
        #expect(model.insight == nil)
        #expect(model.phase == .choosing)
        model.label = "  "
        #expect(!model.canName)
    }

    @Test func aNamingErrorCanBeRetried() async {
        let model = makeModel(client: TasseClient(failure: .rateLimited))
        await model.load(ObjectImages.jpeg())
        model.name()
        await model.waitForName()

        #expect(model.namingError == .rateLimited)
        #expect(model.phase == .choosing)
        #expect(model.canName)
    }

    /// The image classifier needs hardware the iOS Simulator lacks; the learner can still type the name.
    @Test func whenClassificationFailsTheLearnerTypesWhatItIs() async {
        let model = ObjectCaptureModel(
            settings: settings,
            classify: { _ throws(CaptureError) in throw .recognitionFailed },
            destination: { [destination] _ in destination }
        ) {
            InsightService(client: TasseClient(), strategy: .stepwise, source: InsightSource(providerID: "test"))
        }
        await model.load(ObjectImages.jpeg())

        #expect(model.phase == .choosing)
        #expect(model.labels.isEmpty)
        #expect(model.displayImage != nil)
        #expect(!model.canName)
        model.label = "cup"
        #expect(model.canName)
    }

    @Test func whenPhotosMayBeSentTheNamingRequestCarriesASmallCopy() async throws {
        let client = TasseClient(supportsImages: true)
        let model = makeModel(client: client, sharesPhoto: true)
        await model.load(ObjectImages.jpeg())
        #expect(model.sendsPhoto)
        model.name()
        await model.waitForName()

        #expect(model.phase == .named)
        let image = try #require(client.requests.withLock { $0.first?.image })
        let sent = try #require(ImageThumbnailer.image(of: image.jpegData, maximumPixelSize: 4096))
        #expect(max(sent.width, sent.height) <= ImageThumbnailer.maximumPixelSize)
    }

    @Test func otherwiseOnlyTheLabelIsSent() async throws {
        let client = TasseClient(supportsImages: true)
        let model = makeModel(client: client)
        await model.load(ObjectImages.jpeg())
        #expect(!model.sendsPhoto)
        model.name()
        await model.waitForName()

        #expect(client.requests.withLock { $0.count } == 1)
        #expect(client.requests.withLock { $0.first?.image } == nil)
    }

    @Test func whenPhotosMayBeSentTheLabelCanBeLeftEmpty() async {
        let model = makeModel(sharesPhoto: true)
        await model.load(ObjectImages.jpeg())
        model.label = ""
        #expect(model.canName)

        let labelOnly = makeModel()
        await labelOnly.load(ObjectImages.jpeg())
        labelOnly.label = ""
        #expect(!labelOnly.canName)
    }

    @Test func dataThatIsNotAnImageFails() async {
        let model = makeModel()
        await model.load(Data("nope".utf8))
        #expect(model.phase == .failed(.unreadableImage))
    }

    @Test func aCancelledLoadLeavesTheCaptureEmpty() async {
        let model = makeModel()
        let load = Task { await model.load(ObjectImages.jpeg()) }
        load.cancel()
        await load.value
        #expect(model.phase == .empty)
    }
}

/// Answers every object-naming prompt with "die Tasse" and keeps the requests.
private final class TasseClient: GenerationClient {
    let failure: AIError?
    let supportsImages: Bool
    let requests = Mutex<[GenerationRequest]>([])

    init(failure: AIError? = nil, supportsImages: Bool = false) {
        self.failure = failure
        self.supportsImages = supportsImages
    }

    func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent {
        requests.withLock { $0.append(request) }
        if let failure { throw failure }
        do {
            return try GeneratedContent(json: #"{"name":"Tasse","article":"die","translation":"fincan","meaning":"İçecek içmek için kullanılan kulplu küçük kap.","example":"Die Tasse steht auf dem Tisch.","exampleTranslation":"Fincan masanın üstünde duruyor."}"#)
        } catch {
            throw .invalidOutput("bad canned JSON")
        }
    }
}

private final class SavingDestination: CaptureDestination {
    var photo: Data?
    var saved: [WordInsight] = []
    var source: CaptureSource?

    func savedTranslation(lemma: String, language: LanguageCode) -> String? { nil }

    func save(_ insight: WordInsight, captureSource: CaptureSource) throws {
        saved.append(insight)
        source = captureSource
    }
}
#endif
