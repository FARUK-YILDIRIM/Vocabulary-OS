import Foundation
import SwiftData
import VocabularyCore

/// Reviews in the store (ADR-007): today's queues, and answers that go through the scheduler into
/// the review log.
@MainActor
public final class ReviewRepository {
    private let words: WordRepository
    private let scheduler: ReviewScheduler
    private var context: ModelContext { words.context }

    public init(words: WordRepository, scheduler: ReviewScheduler = ReviewScheduler()) {
        self.words = words
        self.scheduler = scheduler
    }

    /// Today's queue for one language, within the daily limits.
    public func queue(language: LanguageCode, limits: ReviewLimits, now: Date = .now, calendar: Calendar = .current) throws -> DailyQueue {
        let code = language.rawValue
        // New words are due from the distant past, so this fetches them too.
        let due = try context.fetch(FetchDescriptor<VocabularyEntry>(predicate: #Predicate { $0.languageCode == code && $0.dueAt <= now }))
        return DailyQueue(
            cards: due.map { DailyQueue.Card(id: $0.id, state: $0.cardState, createdAt: $0.createdAt) },
            limits: limits,
            done: try progress(language: language, now: now, calendar: calendar),
            now: now
        )
    }

    /// Reviews and new words already done today in one language; they count against the limits.
    public func progress(language: LanguageCode, now: Date = .now, calendar: Calendar = .current) throws -> DailyQueue.Progress {
        let code = language.rawValue
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let logs = try context.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate {
            $0.languageCode == code && $0.reviewedAt >= start && $0.reviewedAt < end && $0.changedSchedule == true
        }))
        let newWords = logs.filter(\.wasNew).count
        return DailyQueue.Progress(reviews: logs.count - newWords, newWords: newWords)
    }

    public func entry(id: UUID) throws -> VocabularyEntry? {
        var descriptor = FetchDescriptor<VocabularyEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Records an answer. The first answer of the day moves the word's schedule; every answer is
    /// logged.
    @discardableResult
    public func record(
        _ rating: ReviewRating,
        for entry: VocabularyEntry,
        mode: ReviewMode,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> ReviewLog {
        let before = entry.cardState
        let after = scheduler.schedule(before, rating: rating, now: now, calendar: calendar)
        entry.cardState = after
        let log = ReviewLog(entry: entry, rating: rating, mode: mode, reviewedAt: now, before: before, after: after)
        context.insert(log)
        try context.save()
        return log
    }
}
