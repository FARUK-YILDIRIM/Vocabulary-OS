import Foundation
import SwiftData
import VocabularyCore

/// A generated podcast (SPEC C9, ADR-008). Only the script is stored and synced; every device
/// speaks it with its own voices.
///
/// CloudKit rules (ADR-002): every property has a default. Words are kept as IDs, so deleting a word
/// leaves the episode intact.
@Model
public final class PodcastEpisode {
    public var id: UUID = UUID()
    public var title: String = ""
    public var languageCode: String = ""
    public var nativeLanguageCode: String = ""
    public var levelRaw: String = LanguageLevel.a2.rawValue
    public var styleRaw: String = PodcastStyle.dialogue.rawValue
    public var lengthRaw: String = PodcastLength.short.rawValue
    /// `PodcastScript` as JSON.
    public var scriptData: Data?
    /// IDs of the saved words the script uses, as JSON.
    public var wordIDsData: Data?
    public var providerID: String = ""
    public var modelID: String?
    public var createdAt: Date = Date.now
    /// The segment to continue from.
    public var resumeSegment: Int = 0

    public init(
        script: PodcastScript,
        wordIDs: [UUID],
        language: LanguageCode,
        nativeLanguage: LanguageCode,
        level: LanguageLevel,
        style: PodcastStyle,
        length: PodcastLength,
        source: InsightSource
    ) {
        self.title = script.title
        self.scriptData = try? JSONEncoder().encode(script)
        self.wordIDsData = try? JSONEncoder().encode(wordIDs)
        self.languageCode = language.rawValue
        self.nativeLanguageCode = nativeLanguage.rawValue
        self.levelRaw = level.rawValue
        self.styleRaw = style.rawValue
        self.lengthRaw = length.rawValue
        self.providerID = source.providerID
        self.modelID = source.modelID
    }

    public var script: PodcastScript {
        scriptData.flatMap { try? JSONDecoder().decode(PodcastScript.self, from: $0) } ?? PodcastScript(title: title, segments: [])
    }

    public var wordIDs: [UUID] {
        wordIDsData.flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? []
    }

    public var language: LanguageCode? { LanguageCode(rawValue: languageCode) }
    public var level: LanguageLevel { LanguageLevel(rawValue: levelRaw) ?? .a2 }
    public var style: PodcastStyle { PodcastStyle(rawValue: styleRaw) ?? .dialogue }
    public var length: PodcastLength { PodcastLength(rawValue: lengthRaw) ?? .short }
}
