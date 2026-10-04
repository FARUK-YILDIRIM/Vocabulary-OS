import Foundation

/// Spaced-repetition state of one word (ADR-007). New words start due immediately.
public struct CardState: Codable, Hashable, Sendable {
    public var ease: Double
    public var intervalDays: Int
    public var repetitions: Int
    public var lapses: Int
    public var dueAt: Date
    public var lastReviewedAt: Date?

    public init(
        ease: Double = 2.5,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        lapses: Int = 0,
        dueAt: Date = .distantPast,
        lastReviewedAt: Date? = nil
    ) {
        self.ease = ease
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.lapses = lapses
        self.dueAt = dueAt
        self.lastReviewedAt = lastReviewedAt
    }

    /// Never reviewed yet.
    public var isNew: Bool { lastReviewedAt == nil }

    /// Due at `date`: new words always are, others from the start of their due day.
    public func isDue(at date: Date) -> Bool {
        dueAt <= date
    }

    /// Whether the word was already reviewed on the calendar day of `date`.
    public func wasReviewed(on date: Date, calendar: Calendar) -> Bool {
        lastReviewedAt.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    }

    /// An interval this long means the word is well known (SPEC C4 "mastered" filter).
    public static let masteredIntervalDays = 21
}

/// Where a word was captured (SPEC C5, C6).
public enum CaptureSource: String, Codable, Sendable, CaseIterable {
    /// `services` is the macOS Services menu.
    case text, shareSheet, services, page, object, imported
}

extension String {
    /// Case- and diacritic-insensitive key used to find the same word captured twice.
    public var matchingKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
