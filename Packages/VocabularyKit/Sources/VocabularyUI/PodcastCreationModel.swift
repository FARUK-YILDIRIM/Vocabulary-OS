import Foundation
import Observation
import VocabularyAI
import VocabularyCore
import VocabularyData

/// Writes a podcast episode with the learner's AI provider and saves it (SPEC C9).
@Observable
public final class PodcastCreationModel {
    public enum Phase: Equatable {
        case idle
        case writing
        case failed(String)
    }

    /// A podcast uses 3 to 12 saved words.
    public static let wordCount = 3...12

    public private(set) var phase = Phase.idle

    @ObservationIgnored private let podcasts: PodcastRepository
    @ObservationIgnored private let service: () -> PodcastService

    /// - Parameter service: built when writing starts, so a newly chosen provider takes effect.
    public init(podcasts: PodcastRepository, service: @escaping () -> PodcastService) {
        self.podcasts = podcasts
        self.service = service
    }

    /// Writes and saves an episode; `nil` if writing failed or the task was cancelled.
    public func create(
        words: [VocabularyEntry],
        language: LanguageCode,
        nativeLanguage: LanguageCode,
        level: LanguageLevel,
        length: PodcastLength,
        style: PodcastStyle
    ) async -> PodcastEpisode? {
        guard Self.wordCount.contains(words.count), phase != .writing else { return nil }
        phase = .writing
        let service = service()
        let request = PodcastRequest(
            words: words.map(\.quizWord), language: language, nativeLanguage: nativeLanguage,
            level: level, length: length, style: style
        )
        let script: PodcastScript
        do throws(AIError) {
            script = try await service.script(for: request)
        } catch {
            phase = Task.isCancelled || error == .cancelled ? .idle : .failed(error.localizedDescription)
            return nil
        }
        // The learner left before the script was ready.
        guard !Task.isCancelled else {
            phase = .idle
            return nil
        }
        do {
            let episode = try podcasts.save(
                script, words: words, language: language, nativeLanguage: nativeLanguage,
                level: level, style: style, length: length, source: service.source
            )
            phase = .idle
            return episode
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }
}
