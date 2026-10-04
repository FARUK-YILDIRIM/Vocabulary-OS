import Foundation
import Testing
import VocabularyCore
@testable import VocabularyData

@MainActor
@Suite struct PodcastRepositoryTests {
    private let words: WordRepository
    private let podcasts: PodcastRepository

    init() throws {
        words = WordRepository(container: try VocabularyStore.makeContainer(inMemory: true, cloudSync: false))
        podcasts = PodcastRepository(words: words)
    }

    private let script = PodcastScript(title: "Am Bahnhof", segments: [
        PodcastSegment(speaker: .host, text: "Der Zug kommt."),
        PodcastSegment(speaker: .guest, text: "Gut."),
    ])

    @Test func savesAnEpisodeWithItsScriptAndWords() throws {
        let zug = try words.save(
            WordInsight(term: "Zug", lemma: "Zug", language: .german, nativeLanguage: .turkish, translation: "tren",
                        meaning: "Raylı taşıt.", source: InsightSource(providerID: "test")),
            captureSource: .text
        )
        let episode = try podcasts.save(script, words: [zug], language: .german, nativeLanguage: .turkish,
                                        level: .a2, style: .dialogue, length: .short,
                                        source: InsightSource(providerID: "apple-on-device"))

        #expect(episode.title == "Am Bahnhof")
        #expect(episode.script == script)
        #expect(episode.level == .a2 && episode.style == .dialogue && episode.length == .short)
        #expect(try podcasts.words(in: episode).map(\.term) == ["Zug"])
        #expect(try podcasts.episodes(language: .german).map(\.id) == [episode.id])
        #expect(try podcasts.episodes(language: .english).isEmpty)
    }

    @Test func remembersWhereToResumeAndDeletes() throws {
        let episode = try podcasts.save(script, words: [], language: .german, nativeLanguage: .turkish,
                                        level: .b1, style: .story, length: .long, source: InsightSource(providerID: "test"))
        try podcasts.setResumeSegment(1, for: episode)
        #expect(episode.resumeSegment == 1)
        try podcasts.delete(episode)
        #expect(try podcasts.episodes(language: .german).isEmpty)
    }

    @Test func aDeletedWordLeavesTheEpisode() throws {
        let zug = try words.save(
            WordInsight(term: "Zug", lemma: "Zug", language: .german, nativeLanguage: .turkish, translation: "tren",
                        meaning: "Raylı taşıt.", source: InsightSource(providerID: "test")),
            captureSource: .text
        )
        let episode = try podcasts.save(script, words: [zug], language: .german, nativeLanguage: .turkish,
                                        level: .a2, style: .dialogue, length: .short, source: InsightSource(providerID: "test"))
        try words.delete(zug)
        #expect(try podcasts.words(in: episode).isEmpty)
        #expect(episode.script.segments.count == 2)
    }
}
