import Foundation
import FoundationModels
import Testing
import VocabularyAI
import VocabularyCore
import VocabularyData
@testable import VocabularyUI

@Suite struct CaptureModelTests {
    private let settings: SettingsStore
    private let destination = RecordingDestination()

    init() throws {
        settings = SettingsStore(backing: InMemoryKeyValueBacking())
        settings.profile = try LearnerProfile(native: .turkish, learning: [.english, .german])
    }

    private func model(_ text: String, client: CannedClient = CannedClient()) -> CaptureModel {
        CaptureModel(text: text, settings: settings, destination: destination) {
            InsightService(client: client, strategy: .stepwise, source: InsightSource(providerID: "test"))
        }
    }

    @Test func tappingAWordPicksItsSentenceAndLanguage() {
        let model = model("Cookies are tasty. This website uses cookies for tracking.")
        let index = model.tokens.tokens.lastIndex { $0.text == "cookies" }!
        model.tap(tokenAt: index)

        #expect(model.term == "cookies")
        #expect(model.sentence == "This website uses cookies for tracking.")
        #expect(model.language == .english)
        #expect(model.phase == .ready)
    }

    @Test func aLoneWordIsSelectedRightAwayWithoutASentence() {
        let model = model("Hand")
        #expect(model.selection == 0...0)
        #expect(model.sentence == nil)
        #expect(model.route == .ambiguous([.english, .german]))
        #expect(model.language == .english)
        #expect(model.languageChoices == [.english, .german])
    }

    @Test func aSentenceInAnotherLanguageOffersToAddIt() {
        let model = model("Je voudrais un café, s'il vous plaît.")
        model.tap(tokenAt: model.tokens.tokens.firstIndex { $0.text == "café" }!)

        #expect(model.language == nil)
        #expect(model.suggestedNewLanguage == .french)
        #expect(!model.canExplain)

        model.addToLearningLanguages(.french)
        #expect(settings.profile?.learning == [.english, .german, .french])
        #expect(model.language == .french)
        #expect(model.canExplain)
    }

    @Test func explainingAndSavingDeliversTheInsight() async {
        let model = model("This website uses cookies for tracking.")
        model.tap(tokenAt: 3)
        model.explain()
        await model.waitForExplanation()

        #expect(model.phase == .explained)
        #expect(model.insight?.translation == "çerez")

        model.save()
        #expect(model.phase == .saved)
        #expect(destination.saved.map(\.insight.translation) == ["çerez"])
        #expect(destination.saved.first?.source == .text)
    }

    @Test func failuresCanBeRetried() async {
        let model = model("This website uses cookies for tracking.", client: CannedClient(failure: .rateLimited))
        model.tap(tokenAt: 3)
        model.explain()
        await model.waitForExplanation()
        #expect(model.phase == .failed(.rateLimited))
        #expect(model.canExplain)
    }

    @Test func choosingAnotherWordDiscardsTheInsight() async {
        let model = model("This website uses cookies for tracking.")
        model.tap(tokenAt: 3)
        model.explain()
        await model.waitForExplanation()
        model.tap(tokenAt: 3) // deselect
        #expect(model.insight == nil)
        #expect(model.term == nil)
        #expect(model.phase == .idle)
    }

    @Test func warnsWhenTheWordIsAlreadySaved() async {
        destination.existing = ["cookie": "çerez"]
        let model = model("This website uses cookies for tracking.")
        model.tap(tokenAt: 3)
        model.explain()
        await model.waitForExplanation()
        #expect(model.duplicateTranslation == "çerez")
    }
}

private final class RecordingDestination: CaptureDestination {
    var saved: [(insight: WordInsight, source: CaptureSource)] = []
    var existing: [String: String] = [:]

    func savedTranslation(lemma: String, language: LanguageCode) -> String? {
        existing[lemma]
    }

    func save(_ insight: WordInsight, captureSource: CaptureSource) throws {
        saved.append((insight, captureSource))
    }
}

/// Answers the on-device insight steps with canned JSON, chosen by the schema's title.
struct CannedClient: GenerationClient {
    var failure: AIError?

    func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent {
        if let failure { throw failure }
        let schemaJSON = (try? JSONEncoder().encode(schema)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        let json = schemaJSON.contains("\"title\":\"Sense\"") || schemaJSON.contains("\"title\" : \"Sense\"")
            ? #"{"situation":"a site tracks you","englishWord":"cookie","englishGloss":"a small file a website stores","partOfSpeech":"noun"}"#
            : #"{"translation":"çerez","meaning":"Web sitelerinin sakladığı küçük veri dosyası."}"#
        do {
            return try GeneratedContent(json: json)
        } catch {
            throw .invalidOutput("bad canned JSON")
        }
    }
}
