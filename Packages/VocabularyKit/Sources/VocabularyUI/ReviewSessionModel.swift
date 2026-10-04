import Foundation
import Observation
import VocabularyCore
import VocabularyData

/// A flashcard session for one language (SPEC C7): show a word, reveal its meaning, rate it.
@Observable
public final class ReviewSessionModel {
    public let language: LanguageCode
    /// Words in the session when it started.
    public let total: Int
    public private(set) var current: VocabularyEntry?
    public private(set) var isRevealed = false
    /// Words done for this session; a word answered Again isn't done yet.
    public private(set) var finished = 0
    public private(set) var ratings: [ReviewRating: Int] = [:]
    public private(set) var errorMessage: String?

    private var queue: DailyQueue
    private let repository: ReviewRepository
    private let scheduler = ReviewScheduler()
    private let calendar: Calendar
    private let now: () -> Date

    public init(
        language: LanguageCode,
        limits: ReviewLimits,
        repository: ReviewRepository,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date.now }
    ) throws {
        self.language = language
        self.repository = repository
        self.calendar = calendar
        self.now = now
        let queue = try repository.queue(language: language, limits: limits, now: now(), calendar: calendar)
        self.queue = queue
        total = queue.remaining.count
        showNext()
    }

    public var isFinished: Bool { current == nil }

    public func reveal() {
        isRevealed = true
    }

    public func rate(_ rating: ReviewRating) {
        guard let current else { return }
        do {
            try repository.record(rating, for: current, mode: .flashcard, now: now(), calendar: calendar)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        errorMessage = nil
        ratings[rating, default: 0] += 1
        if rating != .again {
            finished += 1
        }
        queue.answer(rating)
        showNext()
    }

    /// The interval in days the rating would give the current word, or `nil` when the answer won't
    /// move its schedule because it already changed today.
    public func intervalPreview(for rating: ReviewRating) -> Int? {
        guard let state = current?.cardState else { return nil }
        let next = scheduler.schedule(state, rating: rating, now: now(), calendar: calendar)
        return next == state ? nil : next.intervalDays
    }

    private func showNext() {
        isRevealed = false
        current = nil
        while let id = queue.current {
            if let entry = try? repository.entry(id: id) {
                current = entry
                return
            }
            // Deleted while the session was open.
            queue.answer(.good)
        }
    }
}
