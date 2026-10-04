import AVFAudio
import Foundation
import Observation
import VocabularyCore

/// One stretch of speech: a word to hear, or a line of a podcast.
public struct SpeechSegment: Sendable, Hashable {
    public var text: String
    public var language: LanguageCode
    /// A voice from `VoiceCatalog`; the language's default voice when `nil`.
    public var voiceID: String?
    /// 1 is normal. A dialogue with only one voice lowers the second speaker.
    public var pitch: Float

    public init(text: String, language: LanguageCode, voiceID: String? = nil, pitch: Float = 1) {
        self.text = text
        self.language = language
        self.voiceID = voiceID
        self.pitch = pitch
    }
}

/// What makes the sound: the system synthesizer in the app, a recorder in tests.
@MainActor
public protocol SpeechEngine: AnyObject {
    /// Called when a segment ends on its own, not when it is stopped.
    var onFinish: (() -> Void)? { get set }
    /// - Parameter speed: 0.8 to 1.2 times the normal speaking rate.
    func speak(_ segment: SpeechSegment, speed: Double)
    func pause()
    func resume()
    func stop()
}

/// Speaks words and podcast scripts segment by segment (ADR-008), with pause, skip and speed.
@MainActor
@Observable
public final class SpeechPlayer {
    public enum State: Equatable {
        case idle, playing, paused
    }

    public static let speedRange = 0.8...1.2

    public private(set) var state = State.idle
    public private(set) var segments: [SpeechSegment] = []
    /// The segment being spoken, for highlighting a transcript.
    public private(set) var currentIndex: Int? {
        didSet {
            if currentIndex != oldValue { onPositionChange?(currentIndex) }
        }
    }
    /// Called whenever `currentIndex` changes: `nil` once the last segment ends or playback stops.
    @ObservationIgnored public var onPositionChange: ((Int?) -> Void)?
    /// Applies from the next segment on.
    public var speed = 1.0 {
        didSet {
            let clamped = min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
            if clamped != speed { speed = clamped }
        }
    }

    @ObservationIgnored private let engine: any SpeechEngine
    @ObservationIgnored private let catalog: VoiceCatalog

    public init(engine: any SpeechEngine, catalog: VoiceCatalog) {
        self.engine = engine
        self.catalog = catalog
        engine.onFinish = { [weak self] in self?.segmentFinished() }
    }

    /// The system's voices and synthesizer.
    public convenience init() {
        self.init(engine: SystemSpeechEngine(), catalog: .installed())
    }

    /// Says one word or sentence in its language's best voice.
    public func speak(_ text: String, language: LanguageCode) {
        play([SpeechSegment(text: text, language: language, voiceID: catalog.bestVoice(for: language)?.id)])
    }

    public func play(_ segments: [SpeechSegment], from index: Int = 0) {
        if state != .idle { engine.stop() }
        self.segments = segments
        guard segments.indices.contains(index) else { return finish() }
        currentIndex = index
        state = .playing
        engine.speak(segments[index], speed: speed)
    }

    public func pause() {
        guard state == .playing else { return }
        engine.pause()
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        engine.resume()
        state = .playing
    }

    public func stop() {
        guard state != .idle else { return }
        engine.stop()
        finish()
    }

    public func next() {
        guard let currentIndex else { return }
        jump(to: currentIndex + 1)
    }

    public func previous() {
        guard let currentIndex else { return }
        jump(to: max(0, currentIndex - 1))
    }

    private func jump(to index: Int) {
        engine.stop()
        guard segments.indices.contains(index) else { return finish() }
        currentIndex = index
        state = .playing
        engine.speak(segments[index], speed: speed)
    }

    private func segmentFinished() {
        guard state != .idle, let currentIndex else { return }
        let next = currentIndex + 1
        guard segments.indices.contains(next) else { return finish() }
        self.currentIndex = next
        // A paused player that hears a late finish stays paused on the next segment.
        if state == .playing {
            engine.speak(segments[next], speed: speed)
        }
    }

    private func finish() {
        state = .idle
        currentIndex = nil
    }
}

/// `AVSpeechSynthesizer` behind `SpeechEngine`.
@MainActor
public final class SystemSpeechEngine: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate {
    public var onFinish: (() -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private var current: ObjectIdentifier?

    override public init() {
        super.init()
        synthesizer.delegate = self
    }

    public func speak(_ segment: SpeechSegment, speed: Double) {
        #if os(iOS)
        // Spoken content is the point of a listen button, so it plays with the ringer off too.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.voice = segment.voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? AVSpeechSynthesisVoice(language: segment.language.rawValue)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
        utterance.pitchMultiplier = segment.pitch
        current = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    public func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    public func resume() {
        synthesizer.continueSpeaking()
    }

    public func stop() {
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
        // Skipping stops and speaks again right away; only a stop that nothing follows ends the session.
        Task { @MainActor [weak self] in
            self?.endSessionIfQuiet()
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finished = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            // A stopped utterance can still report finishing; only the current one counts.
            guard let self, self.current == finished else { return }
            self.current = nil
            self.onFinish?()
            self.endSessionIfQuiet()
        }
    }

    /// Other apps' audio stays ducked while the session is active, so it ends once nothing is spoken.
    private func endSessionIfQuiet() {
        guard current == nil else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
