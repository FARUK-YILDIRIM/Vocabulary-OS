import AVFAudio
import Foundation
import VocabularyCore

/// An installed voice as the catalog sees it; tests build these by hand.
public struct VoiceDescriptor: Sendable, Hashable, Identifiable {
    public enum Quality: Int, Sendable, Comparable {
        case standard = 1, enhanced, premium

        public static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Gender: Sendable, Hashable {
        case unspecified, male, female
    }

    /// `AVSpeechSynthesisVoice.identifier`.
    public let id: String
    public let name: String
    /// BCP-47, such as "en-US".
    public let language: String
    public let quality: Quality
    public let gender: Gender
    /// Novelty and personal voices, which don't suit lessons.
    public let isSpecial: Bool

    /// A voice with a gender: Apple's regular voices have one, the robotic-sounding extras don't.
    var isRegular: Bool { gender != .unspecified }

    public init(id: String, name: String, language: String, quality: Quality, gender: Gender, isSpecial: Bool = false) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
        self.gender = gender
        self.isSpecial = isSpecial
    }
}

extension VoiceDescriptor {
    init(_ voice: AVSpeechSynthesisVoice) {
        let quality: Quality = switch voice.quality {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .standard
        }
        let gender: Gender = switch voice.gender {
        case .male: .male
        case .female: .female
        default: .unspecified
        }
        self.init(
            id: voice.identifier,
            name: voice.name,
            language: voice.language,
            quality: quality,
            gender: gender,
            isSpecial: !voice.voiceTraits.isDisjoint(with: [.isNoveltyVoice, .isPersonalVoice])
        )
    }
}

/// Chooses voices from those installed (ADR-008): the best quality for the language, in the region
/// the language is usually heard in, and two different voices for a dialogue.
public struct VoiceCatalog: Sendable {
    public let voices: [VoiceDescriptor]

    public init(voices: [VoiceDescriptor]) {
        self.voices = voices
    }

    /// The voices installed on this device.
    public static func installed() -> VoiceCatalog {
        VoiceCatalog(voices: AVSpeechSynthesisVoice.speechVoices().map(VoiceDescriptor.init))
    }

    /// Voices that speak the language, best first: higher quality, then regular voices before ones
    /// without a gender (the robotic-sounding Eddy, Flo, Grandma … that macOS ships at the same
    /// quality), then the language's usual region (en-US, pt-BR, zh-TW for Traditional Chinese),
    /// then by name.
    public func voices(for language: LanguageCode) -> [VoiceDescriptor] {
        let wanted = Locale.Language(identifier: language.rawValue)
        let usualRegion = Locale.Language(identifier: wanted.maximalIdentifier).region
        return voices
            .filter { !$0.isSpecial && Self.speaks($0, wanted) }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
                if lhs.isRegular != rhs.isRegular { return lhs.isRegular }
                let lhsUsual = Locale.Language(identifier: lhs.language).region == usualRegion
                let rhsUsual = Locale.Language(identifier: rhs.language).region == usualRegion
                if lhsUsual != rhsUsual { return lhsUsual }
                return lhs.name < rhs.name
            }
    }

    public func bestVoice(for language: LanguageCode) -> VoiceDescriptor? {
        voices(for: language).first
    }

    /// Two voices for a dialogue, preferring different genders. The guest is `nil` without a second
    /// regular voice; the player then lowers the host voice's pitch for the guest.
    public func dialogueVoices(for language: LanguageCode) -> (host: VoiceDescriptor, guest: VoiceDescriptor?)? {
        let candidates = voices(for: language)
        guard let host = candidates.first else { return nil }
        let others = candidates.dropFirst().filter(\.isRegular)
        let guest = others.first { $0.gender != host.gender } ?? others.first
        return (host, guest)
    }

    /// Same language, and the same script where a language has two (Chinese).
    private static func speaks(_ voice: VoiceDescriptor, _ wanted: Locale.Language) -> Bool {
        let language = Locale.Language(identifier: voice.language)
        guard language.languageCode == wanted.languageCode
            || (Self.norwegian.contains(language.languageCode?.identifier ?? "") && Self.norwegian.contains(wanted.languageCode?.identifier ?? ""))
        else { return false }
        let script = Locale.Language(identifier: language.maximalIdentifier).script
        let wantedScript = Locale.Language(identifier: wanted.maximalIdentifier).script
        return script == wantedScript
    }

    /// Voices for Norwegian Bokmål may be labeled "no" or "nb".
    private static let norwegian: Set<String> = ["nb", "no"]
}
