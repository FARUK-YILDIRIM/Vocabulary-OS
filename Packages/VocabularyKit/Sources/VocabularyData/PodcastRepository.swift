import Foundation
import SwiftData
import VocabularyCore

/// Podcast episodes in the store (SPEC C9).
@MainActor
public final class PodcastRepository {
    private let words: WordRepository
    private var context: ModelContext { words.context }

    public init(words: WordRepository) {
        self.words = words
    }

    @discardableResult
    public func save(
        _ script: PodcastScript,
        words: [VocabularyEntry],
        language: LanguageCode,
        nativeLanguage: LanguageCode,
        level: LanguageLevel,
        style: PodcastStyle,
        length: PodcastLength,
        source: InsightSource
    ) throws -> PodcastEpisode {
        let episode = PodcastEpisode(
            script: script, wordIDs: words.map(\.id), language: language, nativeLanguage: nativeLanguage,
            level: level, style: style, length: length, source: source
        )
        context.insert(episode)
        try context.save()
        return episode
    }

    /// Episodes in one language, newest first.
    public func episodes(language: LanguageCode) throws -> [PodcastEpisode] {
        let code = language.rawValue
        return try context.fetch(FetchDescriptor<PodcastEpisode>(
            predicate: #Predicate { $0.languageCode == code },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    /// The saved words an episode uses, skipping any deleted since.
    public func words(in episode: PodcastEpisode) throws -> [VocabularyEntry] {
        let ids = episode.wordIDs
        guard !ids.isEmpty else { return [] }
        let found = try context.fetch(FetchDescriptor<VocabularyEntry>(predicate: #Predicate { ids.contains($0.id) }))
        return ids.compactMap { id in found.first { $0.id == id } }
    }

    public func setResumeSegment(_ segment: Int, for episode: PodcastEpisode) throws {
        episode.resumeSegment = max(0, segment)
        try context.save()
    }

    public func delete(_ episode: PodcastEpisode) throws {
        context.delete(episode)
        try context.save()
    }
}
