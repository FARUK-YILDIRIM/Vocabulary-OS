import Testing
import VocabularyCore
@testable import VocabularySpeech

@Suite struct PodcastVoicesTests {
    private func voice(_ id: String, _ language: String, _ gender: VoiceDescriptor.Gender = .female) -> VoiceDescriptor {
        VoiceDescriptor(id: id, name: id, language: language, quality: .enhanced, gender: gender)
    }

    private let dialogue = PodcastScript(title: "Am Bahnhof", segments: [
        PodcastSegment(speaker: .host, text: "Hallo!"),
        PodcastSegment(speaker: .guest, text: "Guten Tag!"),
        PodcastSegment(speaker: .host, text: "Wo ist der Zug?"),
    ])

    @Test func aDialogueGivesEachHostAVoice() {
        let catalog = VoiceCatalog(voices: [voice("anna", "de-DE"), voice("markus", "de-DE", .male)])
        let voices = catalog.podcastVoices(style: .dialogue, language: .german)
        #expect(voices.notice == nil)

        let segments = voices.segments(for: dialogue, language: .german)
        #expect(segments.map(\.text) == ["Hallo!", "Guten Tag!", "Wo ist der Zug?"])
        #expect(segments.map(\.voiceID) == ["anna", "markus", "anna"])
        #expect(segments.map(\.pitch) == [1, 1, 1])
        #expect(segments.allSatisfy { $0.language == .german })
    }

    @Test func withOneVoiceTheGuestSpeaksAtAnotherPitch() {
        let voices = VoiceCatalog(voices: [voice("anna", "de-DE")]).podcastVoices(style: .dialogue, language: .german)
        #expect(voices.notice == .oneVoice)

        let segments = voices.segments(for: dialogue, language: .german)
        #expect(segments.map(\.voiceID) == ["anna", "anna", "anna"])
        #expect(segments[0].pitch == 1)
        #expect(segments[1].pitch < 1)
    }

    @Test func aStoryNeedsOnlyOneVoice() {
        let voices = VoiceCatalog(voices: [voice("anna", "de-DE")]).podcastVoices(style: .story, language: .german)
        #expect(voices.notice == nil)
        let story = PodcastScript(title: "Der Zug", segments: [PodcastSegment(speaker: .narrator, text: "Es war einmal ein Zug.")])
        #expect(voices.segments(for: story, language: .german).map(\.voiceID) == ["anna"])
    }

    @Test func withoutAVoiceTheSystemVoiceReads() {
        let voices = VoiceCatalog(voices: [voice("samantha", "en-US")]).podcastVoices(style: .dialogue, language: .korean)
        #expect(voices.notice == .noVoice)

        let segments = voices.segments(for: dialogue, language: .korean)
        #expect(segments.map(\.voiceID) == [nil, nil, nil])
        #expect(segments[1].pitch != segments[0].pitch, "The hosts still sound different")
    }
}
