import Foundation
import Observation
import os
import VocabularyCore
import VocabularyData
import VocabularySpeech

/// Plays one podcast episode (SPEC C9, ADR-008): speaks the script line by line with the episode's
/// voices, remembers the line the learner is on, and links the saved words in the transcript.
@Observable
public final class PodcastPlaybackModel {
    /// Transcript links to saved words use this scheme; the player opens them itself.
    public static let wordLinkScheme = "vocabularyos-word"

    public let episode: PodcastEpisode
    public let script: PodcastScript
    public let language: LanguageCode
    public let voices: PodcastVoices
    /// The saved words the episode uses, skipping any deleted since. Values rather than models, so
    /// a word deleted while the player is open leaves nothing dangling.
    public private(set) var words: [QuizWord]
    public let player: SpeechPlayer
    /// The line being spoken, or where Play starts.
    public private(set) var position: Int

    @ObservationIgnored private let podcasts: PodcastRepository
    @ObservationIgnored private let segments: [SpeechSegment]
    @ObservationIgnored private var transcripts: [Int: AttributedString] = [:]
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private let logger = Logger(subsystem: VocabularyCore.logSubsystem, category: VocabularyUI.logCategory)

    /// - Parameter engine: what makes the sound; the system synthesizer when `nil`.
    public init(episode: PodcastEpisode, podcasts: PodcastRepository, catalog: VoiceCatalog = .installed(), engine: (any SpeechEngine)? = nil) {
        self.episode = episode
        self.podcasts = podcasts
        script = episode.script
        language = episode.language ?? .english
        voices = catalog.podcastVoices(style: episode.style, language: language)
        words = Self.savedWords(in: episode, podcasts: podcasts)
        segments = voices.segments(for: script, language: language)
        player = SpeechPlayer(engine: engine ?? SystemSpeechEngine(interruptsOtherAudio: true), catalog: catalog)
        position = min(max(0, episode.resumeSegment), max(0, script.segments.count - 1))
        player.onPositionChange = { [weak self] index in
            self?.positionChanged(to: index)
        }
    }

    public var isPlaying: Bool { player.state == .playing }

    /// 0.8 to 1.2 times the normal rate, from the next line on.
    public var speed: Double {
        get { player.speed }
        set { player.speed = newValue }
    }

    public func togglePlayback() {
        switch player.state {
        case .idle: play(from: position)
        case .playing: pause()
        case .paused: resume()
        }
    }

    public func play(from index: Int) {
        guard segments.indices.contains(index) else { return }
        player.play(segments, from: index)
    }

    public func pause() {
        player.pause()
    }

    public func resume() {
        player.resume()
    }

    public func next() {
        if player.state == .idle {
            move(to: position + 1)
        } else {
            player.next()
        }
    }

    public func previous() {
        if player.state == .idle {
            move(to: position - 1)
        } else {
            player.previous()
        }
    }

    /// Stops speaking and keeps the line for next time, as when the learner leaves the player.
    public func stop() {
        isStopping = true
        defer { isStopping = false }
        player.stop()
    }

    // MARK: Transcript

    /// A line's text with the saved words it uses as links (see `wordID(in:)`).
    public func transcript(for index: Int) -> AttributedString {
        if let cached = transcripts[index] { return cached }
        guard script.segments.indices.contains(index) else { return AttributedString() }
        let text = script.segments[index].text
        var transcript = AttributedString(text)
        for match in WordOccurrences.highlights(words, in: text, language: language) {
            guard let range = Range(match.range, in: transcript) else { continue }
            transcript[range].link = URL(string: "\(Self.wordLinkScheme):\(match.wordID.uuidString)")
            transcript[range].inlinePresentationIntent = .stronglyEmphasized
        }
        transcripts[index] = transcript
        return transcript
    }

    /// The saved word a transcript link points to.
    public static func wordID(in url: URL) -> UUID? {
        guard url.scheme == wordLinkScheme else { return nil }
        return UUID(uuidString: String(url.absoluteString.dropFirst(wordLinkScheme.count + 1)))
    }

    public func word(id: UUID) -> QuizWord? {
        words.first { $0.id == id }
    }

    /// Reads the episode's words again, after one may have been deleted or edited.
    public func reloadWords() {
        words = Self.savedWords(in: episode, podcasts: podcasts)
        transcripts = [:]
    }

    private static func savedWords(in episode: PodcastEpisode, podcasts: PodcastRepository) -> [QuizWord] {
        ((try? podcasts.words(in: episode)) ?? []).map(\.quizWord)
    }

    // MARK: Position

    private func move(to index: Int) {
        let line = min(max(0, index), max(0, segments.count - 1))
        guard line != position else { return }
        position = line
        save(line)
    }

    private func positionChanged(to index: Int?) {
        if let index {
            position = index
            save(index)
        } else if !isStopping {
            // The last line ended; next time starts over.
            position = 0
            save(0)
        }
    }

    private func save(_ line: Int) {
        do {
            try podcasts.setResumeSegment(line, for: episode)
        } catch {
            logger.error("Could not save the podcast position: \(error.localizedDescription, privacy: .public)")
        }
    }
}
