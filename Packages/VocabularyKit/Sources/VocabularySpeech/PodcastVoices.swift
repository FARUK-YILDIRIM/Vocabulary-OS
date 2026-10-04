import Foundation
import VocabularyCore

/// The voices that read a podcast (ADR-008): two installed voices for a dialogue's hosts, the best
/// one for a story's narrator.
public struct PodcastVoices: Sendable, Equatable {
    /// Something the learner should know about how the episode sounds.
    public enum Notice: Sendable, Equatable {
        /// No voice for the language is installed, so the system's default voice reads.
        case noVoice
        /// A dialogue with one installed voice: the guest speaks with it at a lower pitch.
        case oneVoice
    }

    /// The pitch that sets the guest apart when both hosts share a voice.
    public static let sharedVoiceGuestPitch: Float = 0.8

    /// The host's or narrator's voice; `nil` reads with the system's default voice.
    public let host: VoiceDescriptor?
    public let guest: VoiceDescriptor?
    public let notice: Notice?

    public init(host: VoiceDescriptor?, guest: VoiceDescriptor?, style: PodcastStyle) {
        self.host = host
        self.guest = guest
        if host == nil {
            notice = .noVoice
        } else if style == .dialogue && guest == nil {
            notice = .oneVoice
        } else {
            notice = nil
        }
    }

    /// The script as speech, one segment per line or paragraph.
    public func segments(for script: PodcastScript, language: LanguageCode) -> [SpeechSegment] {
        script.segments.map { segment in
            switch segment.speaker {
            case .host, .narrator:
                SpeechSegment(text: segment.text, language: language, voiceID: host?.id)
            case .guest:
                if let guest {
                    SpeechSegment(text: segment.text, language: language, voiceID: guest.id)
                } else {
                    SpeechSegment(text: segment.text, language: language, voiceID: host?.id, pitch: Self.sharedVoiceGuestPitch)
                }
            }
        }
    }
}

extension VoiceCatalog {
    /// The voices for a podcast in the language and style.
    public func podcastVoices(style: PodcastStyle, language: LanguageCode) -> PodcastVoices {
        switch style {
        case .dialogue:
            let pair = dialogueVoices(for: language)
            return PodcastVoices(host: pair?.host, guest: pair?.guest, style: style)
        case .story:
            return PodcastVoices(host: bestVoice(for: language), guest: nil, style: style)
        }
    }
}
