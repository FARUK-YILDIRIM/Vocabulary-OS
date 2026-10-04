import Testing
import VocabularyCore
@testable import VocabularySpeech

@Suite struct VoiceCatalogTests {
    private func voice(_ id: String, _ language: String, _ quality: VoiceDescriptor.Quality = .standard,
                       _ gender: VoiceDescriptor.Gender = .unspecified, special: Bool = false) -> VoiceDescriptor {
        VoiceDescriptor(id: id, name: id, language: language, quality: quality, gender: gender, isSpecial: special)
    }

    @Test func prefersTheBestQualityForTheLanguage() {
        let catalog = VoiceCatalog(voices: [
            voice("samantha", "en-US"),
            voice("ava-premium", "en-US", .premium),
            voice("anna", "de-DE", .enhanced),
            voice("daniel-enhanced", "en-GB", .enhanced),
        ])
        #expect(catalog.bestVoice(for: .english)?.id == "ava-premium")
        #expect(catalog.voices(for: .english).map(\.id) == ["ava-premium", "daniel-enhanced", "samantha"])
        #expect(catalog.bestVoice(for: .german)?.id == "anna")
    }

    @Test func prefersTheLanguagesUsualRegionAtEqualQuality() {
        let catalog = VoiceCatalog(voices: [
            voice("luciana", "pt-BR"), voice("joana", "pt-PT"),
            voice("daniel", "en-GB"), voice("samantha", "en-US"),
        ])
        #expect(catalog.bestVoice(for: .portuguese)?.id == "luciana")
        #expect(catalog.bestVoice(for: .english)?.id == "samantha")
    }

    @Test func matchesTheChineseScript() {
        let catalog = VoiceCatalog(voices: [voice("tingting", "zh-CN"), voice("meijia", "zh-TW"), voice("sinji", "zh-HK")])
        #expect(catalog.bestVoice(for: .chineseSimplified)?.id == "tingting")
        #expect(catalog.bestVoice(for: .chineseTraditional)?.id == "meijia")
    }

    /// macOS ships robotic-sounding voices (Eddy, Flo, Grandma …) at the same quality as the regular
    /// ones; they have no gender, which tells them apart.
    @Test func prefersRegularVoicesOverOnesWithoutAGender() throws {
        let catalog = VoiceCatalog(voices: [
            voice("eddy", "de-DE"), voice("flo", "de-DE"), voice("anna", "de-DE", .standard, .female),
        ])
        #expect(catalog.bestVoice(for: .german)?.id == "anna")
        let pair = try #require(catalog.dialogueVoices(for: .german))
        #expect(pair.guest == nil, "The guest gets Anna's voice at a lower pitch instead")
    }

    /// The old MacinTalk voices (Fred, Ralph …) sound robotic too, though Fred has a gender. Measured:
    /// on a Mac with only default-quality English voices, Fred beat Samantha by name.
    @Test func prefersModernVoicesOverMacinTalkOnes() throws {
        let catalog = VoiceCatalog(voices: [
            voice("com.apple.speech.synthesis.voice.Fred", "en-US", .standard, .male),
            voice("com.apple.voice.compact.en-US.Samantha", "en-US", .standard, .female),
            voice("com.apple.voice.super-compact.en-GB.Daniel", "en-GB", .standard, .male),
        ])
        #expect(catalog.bestVoice(for: .english)?.id == "com.apple.voice.compact.en-US.Samantha")
        let pair = try #require(catalog.dialogueVoices(for: .english))
        #expect(pair.guest?.id == "com.apple.voice.super-compact.en-GB.Daniel", "A dialogue's second voice is never a robotic one")
    }

    @Test func skipsNoveltyAndPersonalVoices() {
        let catalog = VoiceCatalog(voices: [voice("bubbles", "en-US", .premium, special: true), voice("samantha", "en-US")])
        #expect(catalog.bestVoice(for: .english)?.id == "samantha")
    }

    @Test func dialoguesUseTwoVoicesOfDifferentGendersWhenPossible() throws {
        let catalog = VoiceCatalog(voices: [
            voice("anna", "de-DE", .enhanced, .female),
            voice("petra", "de-DE", .standard, .female),
            voice("markus", "de-DE", .standard, .male),
        ])
        let pair = try #require(catalog.dialogueVoices(for: .german))
        #expect(pair.host.id == "anna")
        #expect(pair.guest?.id == "markus")
    }

    @Test func aDialogueWithOneVoiceHasNoGuestVoice() throws {
        let pair = try #require(VoiceCatalog(voices: [voice("yelda", "tr-TR", .standard, .female)]).dialogueVoices(for: .turkish))
        #expect(pair.host.id == "yelda")
        #expect(pair.guest == nil)
    }

    @Test func aLanguageWithoutVoicesHasNone() {
        let catalog = VoiceCatalog(voices: [voice("samantha", "en-US")])
        #expect(catalog.bestVoice(for: .korean) == nil)
        #expect(catalog.dialogueVoices(for: .korean) == nil)
    }
}

@MainActor
@Suite struct SpeechPlayerTests {
    private let engine = RecordingEngine()
    private let catalog = VoiceCatalog(voices: [
        VoiceDescriptor(id: "anna", name: "Anna", language: "de-DE", quality: .enhanced, gender: .female),
    ])

    private func segments(_ texts: [String]) -> [SpeechSegment] {
        texts.map { SpeechSegment(text: $0, language: .german) }
    }

    @Test func playsSegmentsInOrderAsEachFinishes() {
        let player = SpeechPlayer(engine: engine, catalog: catalog)
        player.play(segments(["eins", "zwei", "drei"]))
        #expect(engine.spoken.map(\.text) == ["eins"])
        #expect(player.state == .playing && player.currentIndex == 0)

        engine.finish()
        engine.finish()
        #expect(engine.spoken.map(\.text) == ["eins", "zwei", "drei"])
        engine.finish()
        #expect(player.state == .idle)
        #expect(player.currentIndex == nil)
    }

    @Test func skipsForwardAndBack() {
        let player = SpeechPlayer(engine: engine, catalog: catalog)
        player.play(segments(["eins", "zwei", "drei"]))
        player.next()
        player.next()
        player.previous()
        #expect(engine.spoken.map(\.text) == ["eins", "zwei", "drei", "zwei"])
        #expect(engine.stops == 3)
        #expect(player.currentIndex == 1)
    }

    @Test func reportsEveryChangeOfPosition() {
        let player = SpeechPlayer(engine: engine, catalog: catalog)
        var positions: [Int?] = []
        player.onPositionChange = { positions.append($0) }
        player.play(segments(["eins", "zwei", "drei"]))
        engine.finish()
        player.next()
        player.previous()
        player.stop()
        #expect(positions == [0, 1, 2, 1, nil])
    }

    @Test func pausesResumesAndStops() {
        let player = SpeechPlayer(engine: engine, catalog: catalog)
        player.play(segments(["eins"]))
        player.pause()
        #expect(player.state == .paused && engine.pauses == 1)
        player.resume()
        #expect(player.state == .playing && engine.resumes == 1)
        player.stop()
        #expect(player.state == .idle)
    }

    @Test func speedStaysBetweenPointEightAndOnePointTwo() {
        let player = SpeechPlayer(engine: engine, catalog: catalog)
        player.speed = 2
        #expect(player.speed == 1.2)
        player.speed = 0.5
        #expect(player.speed == 0.8)
        player.play(segments(["eins"]))
        #expect(engine.speeds == [0.8])
    }

    @Test func aSingleWordUsesTheLanguagesBestVoice() {
        let player = SpeechPlayer(engine: engine, catalog: catalog)
        player.speak("Tasse", language: .german)
        #expect(engine.spoken.first?.voiceID == "anna")
        #expect(player.currentIndex == 0)
    }
}

/// Records what the player asks for instead of making sound.
@MainActor
private final class RecordingEngine: SpeechEngine {
    var onFinish: (() -> Void)?
    var spoken: [SpeechSegment] = []
    var speeds: [Double] = []
    var stops = 0
    var pauses = 0
    var resumes = 0

    func speak(_ segment: SpeechSegment, speed: Double) {
        spoken.append(segment)
        speeds.append(speed)
    }

    func pause() { pauses += 1 }
    func resume() { resumes += 1 }
    func stop() { stops += 1 }

    func finish() { onFinish?() }
}
