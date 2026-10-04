import Foundation
import Testing
import VocabularyCore
import VocabularyData
import VocabularySpeech
@testable import VocabularyUI

@Suite struct PodcastPlaybackModelTests {
    private let words: WordRepository
    private let podcasts: PodcastRepository
    private let engine = RecordingEngine()
    private let catalog = VoiceCatalog(voices: [
        VoiceDescriptor(id: "samantha", name: "Samantha", language: "en-US", quality: .enhanced, gender: .female),
        VoiceDescriptor(id: "daniel", name: "Daniel", language: "en-GB", quality: .standard, gender: .male),
    ])
    private let script = PodcastScript(title: "A Rainy Afternoon", segments: [
        PodcastSegment(speaker: .host, text: "Do you like cookies?"),
        PodcastSegment(speaker: .guest, text: "Yes, and I liked your pitch."),
        PodcastSegment(speaker: .host, text: "Thank you!"),
    ])

    init() throws {
        words = WordRepository(container: try VocabularyStore.makeContainer(inMemory: true, cloudSync: false))
        podcasts = PodcastRepository(words: words)
    }

    private func makeEpisode(resumeAt segment: Int = 0) throws -> PodcastEpisode {
        let entries = try ["cookies", "pitch"].map { term in
            try words.save(
                WordInsight(term: term, lemma: term, partOfSpeech: .noun, language: .english, nativeLanguage: .turkish,
                            context: nil, translation: "çeviri", meaning: "Anlam.", source: InsightSource(providerID: "test")),
                captureSource: .text
            )
        }
        let episode = try podcasts.save(
            script, words: entries, language: .english, nativeLanguage: .turkish, level: .a2, style: .dialogue,
            length: .short, source: InsightSource(providerID: "test")
        )
        try podcasts.setResumeSegment(segment, for: episode)
        return episode
    }

    private func makeModel(_ episode: PodcastEpisode) -> PodcastPlaybackModel {
        PodcastPlaybackModel(episode: episode, podcasts: podcasts, catalog: catalog, engine: engine)
    }

    @Test func playsFromWhereTheLearnerStopped() throws {
        let model = makeModel(try makeEpisode(resumeAt: 1))
        #expect(model.position == 1)
        model.togglePlayback()
        #expect(model.isPlaying)
        #expect(engine.spoken.map(\.text) == ["Yes, and I liked your pitch."])
    }

    @Test func speaksEachHostWithTheirOwnVoice() throws {
        let model = makeModel(try makeEpisode())
        model.togglePlayback()
        engine.finish()
        engine.finish()
        #expect(engine.spoken.map(\.voiceID) == ["samantha", "daniel", "samantha"])
        #expect(model.voices.notice == nil)
    }

    @Test func remembersTheLineItIsOn() throws {
        let episode = try makeEpisode()
        let model = makeModel(episode)
        model.togglePlayback()
        engine.finish()
        #expect(episode.resumeSegment == 1)

        model.togglePlayback()
        #expect(!model.isPlaying)
        model.stop()
        #expect(episode.resumeSegment == 1, "Leaving the player keeps the line")
        #expect(model.position == 1)
    }

    @Test func startsOverAfterTheLastLine() throws {
        let episode = try makeEpisode(resumeAt: 2)
        let model = makeModel(episode)
        model.togglePlayback()
        engine.finish()
        #expect(model.player.state == .idle)
        #expect(model.position == 0)
        #expect(episode.resumeSegment == 0)
    }

    @Test func skippingWhileStoppedMovesThePosition() throws {
        let episode = try makeEpisode()
        let model = makeModel(episode)
        model.next()
        model.next()
        model.next()
        #expect(model.position == 2, "It stops at the last line")
        model.previous()
        #expect(model.position == 1)
        #expect(episode.resumeSegment == 1)
        #expect(engine.spoken.isEmpty)
    }

    @Test func playsFromAChosenLine() throws {
        let model = makeModel(try makeEpisode())
        model.play(from: 2)
        #expect(engine.spoken.map(\.text) == ["Thank you!"])
        #expect(model.position == 2)
    }

    @Test func pausesAndResumes() throws {
        let model = makeModel(try makeEpisode())
        model.togglePlayback()
        model.pause()
        #expect(model.player.state == .paused)
        model.resume()
        #expect(model.isPlaying)
    }

    @Test func linksTheSavedWordsInTheTranscript() throws {
        let model = makeModel(try makeEpisode())
        let text = model.transcript(for: 1)
        let links = text.runs.compactMap { run in run.link.map { (String(text[run.range].characters), $0) } }
        #expect(links.map(\.0) == ["pitch"])

        let id = try #require(links.first.flatMap { PodcastPlaybackModel.wordID(in: $0.1) })
        #expect(model.word(id: id)?.term == "pitch")
        #expect(PodcastPlaybackModel.wordID(in: URL(string: "https://example.com")!) == nil)
    }

    @Test func forgetsWordsDeletedWhileOpen() throws {
        let model = makeModel(try makeEpisode())
        #expect(model.words.map(\.term) == ["cookies", "pitch"])
        let pitch = try #require(try words.entries(language: .english).first { $0.term == "pitch" })
        try words.delete(pitch)

        model.reloadWords()
        #expect(model.words.map(\.term) == ["cookies"])
        let text = model.transcript(for: 1)
        #expect(text.runs.allSatisfy { $0.link == nil }, "A deleted word is no longer a link")
    }
}

/// Records what the player asks for instead of making sound.
private final class RecordingEngine: SpeechEngine {
    var onFinish: (() -> Void)?
    var spoken: [SpeechSegment] = []

    func speak(_ segment: SpeechSegment, speed: Double) {
        spoken.append(segment)
    }

    func pause() {}
    func resume() {}
    func stop() {}

    func finish() { onFinish?() }
}
