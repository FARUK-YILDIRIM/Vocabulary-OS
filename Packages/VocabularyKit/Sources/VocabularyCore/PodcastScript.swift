import Foundation

/// How a podcast is told (SPEC C9).
public enum PodcastStyle: String, CaseIterable, Codable, Sendable {
    /// Two hosts talk.
    case dialogue
    /// A narrator tells a story.
    case story
}

/// About two or five minutes (SPEC C9).
public enum PodcastLength: String, CaseIterable, Codable, Sendable {
    case short, long

    public var minutes: Int {
        switch self {
        case .short: 2
        case .long: 5
        }
    }

    /// Words to aim for, at about 130 words a minute, a comfortable pace for learners.
    public var targetWords: Int { minutes * 130 }

    /// Scripts longer than this are rejected.
    public var maximumWords: Int { targetWords * 3 / 2 }
}

/// CEFR level of the language a podcast uses.
public enum LanguageLevel: String, CaseIterable, Codable, Sendable {
    case a1, a2, b1, b2, c1, c2

    /// "A1" … "C2".
    public var label: String { rawValue.uppercased() }
}

public enum PodcastSpeaker: String, CaseIterable, Codable, Sendable {
    case host, guest, narrator
}

/// One turn of a dialogue, or one paragraph of a story.
public struct PodcastSegment: Codable, Hashable, Sendable {
    public var speaker: PodcastSpeaker
    public var text: String

    public init(speaker: PodcastSpeaker, text: String) {
        self.speaker = speaker
        self.text = text
    }
}

/// A podcast's script (ADR-008): spoken on the device, so only the text is stored and synced.
public struct PodcastScript: Codable, Hashable, Sendable {
    public var title: String
    public var segments: [PodcastSegment]

    public init(title: String, segments: [PodcastSegment]) {
        self.title = title
        self.segments = segments
    }

    /// All segments as one text.
    public var text: String {
        segments.map(\.text).joined(separator: "\n")
    }

    public var wordCount: Int {
        segments.reduce(0) { $0 + TokenizedText($1.text).tokens.count }
    }
}
