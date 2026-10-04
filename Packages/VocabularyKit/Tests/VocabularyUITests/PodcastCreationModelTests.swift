import Foundation
import FoundationModels
import Testing
import VocabularyAI
import VocabularyCore
import VocabularyData
@testable import VocabularyUI

@Suite struct PodcastCreationModelTests {
    private let words: WordRepository
    private let podcasts: PodcastRepository
    private let entries: [VocabularyEntry]

    init() throws {
        words = WordRepository(container: try VocabularyStore.makeContainer(inMemory: true, cloudSync: false))
        podcasts = PodcastRepository(words: words)
        entries = try ["cookies", "pitch", "umbrella"].map { [words] term in
            try words.save(
                WordInsight(term: term, lemma: term, partOfSpeech: .noun, language: .english, nativeLanguage: .turkish,
                            context: nil, translation: "çeviri", meaning: "Anlam.", source: InsightSource(providerID: "test")),
                captureSource: .text
            )
        }
    }

    private func makeModel(client: ScriptClient = ScriptClient()) -> PodcastCreationModel {
        PodcastCreationModel(podcasts: podcasts) {
            PodcastService(client: client, strategy: .singleCall, source: InsightSource(providerID: "test", modelID: "model"))
        }
    }

    private func create(_ model: PodcastCreationModel, words: [VocabularyEntry]? = nil) async -> PodcastEpisode? {
        await model.create(words: words ?? entries, language: .english, nativeLanguage: .turkish, level: .b1, length: .short, style: .dialogue)
    }

    @Test func writesAndSavesAnEpisode() async throws {
        let model = makeModel()
        let episode = try #require(await create(model))

        #expect(episode.title == "A Rainy Afternoon")
        #expect(episode.script.segments.count == 4)
        #expect(episode.wordIDs == entries.map(\.id))
        #expect(episode.level == .b1)
        #expect(episode.providerID == "test")
        #expect(try podcasts.episodes(language: .english).count == 1)
        #expect(model.phase == .idle)
    }

    @Test func explainsWhyWritingFailed() async throws {
        let model = makeModel(client: ScriptClient(failure: .network("offline")))
        #expect(await create(model) == nil)
        #expect(model.phase == .failed(AIError.network("offline").localizedDescription))
        #expect(try podcasts.episodes(language: .english).isEmpty)
    }

    @Test func needsThreeToTwelveWords() async throws {
        #expect(PodcastCreationModel.wordCount == 3...12)
        let model = makeModel()
        #expect(await create(model, words: Array(entries.prefix(2))) == nil)
        #expect(model.phase == .idle)
        #expect(try podcasts.episodes(language: .english).isEmpty)
    }

    @Test func aCancelledEpisodeIsNotSaved() async throws {
        let model = makeModel(client: ScriptClient(delay: .seconds(5)))
        // Episodes aren't Sendable, so the task reports only whether one came back.
        let task = Task { await create(model) != nil }
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.phase == .writing)
        task.cancel()
        #expect(await task.value == false)
        #expect(model.phase == .idle)
        #expect(try podcasts.episodes(language: .english).isEmpty)
    }
}

private struct ScriptClient: GenerationClient {
    var failure: AIError?
    var delay: Duration?

    func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent {
        if let failure { throw failure }
        if let delay { try? await Task.sleep(for: delay) }
        do {
            return try GeneratedContent(json: #"{"title":"A Rainy Afternoon","lines":[{"speaker":"host","text":"I baked cookies today."},{"speaker":"guest","text":"Did you bring an umbrella?"},{"speaker":"host","text":"Yes, and I practised my pitch."},{"speaker":"guest","text":"Great, see you soon."}]}"#)
        } catch {
            throw .invalidOutput("bad canned JSON")
        }
    }
}
