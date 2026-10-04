import Foundation
import SwiftData
import VocabularyCore

/// One answer to a review (ADR-007). The log feeds today's limits and statistics, and lets a later
/// scheduler replay the history.
///
/// CloudKit rules (ADR-002): every property has a default, and the relationship is optional with an
/// inverse on `VocabularyEntry.reviewLogs`.
@Model
public final class ReviewLog {
    public var id: UUID = UUID()
    public var entry: VocabularyEntry?
    /// The word's language, so counting today's reviews needs no join.
    public var languageCode: String = ""
    public var reviewedAt: Date = Date.now
    public var ratingRaw: String = ReviewRating.good.rawValue
    public var modeRaw: String = ReviewMode.flashcard.rawValue
    public var intervalBefore: Int = 0
    public var intervalAfter: Int = 0
    public var easeBefore: Double = 2.5
    public var easeAfter: Double = 2.5
    /// The word had never been reviewed: this answer introduced it.
    public var wasNew: Bool = false
    /// Only the first answer of a day moves the schedule; later ones are logged with `false`.
    public var changedSchedule: Bool = true

    public init(entry: VocabularyEntry, rating: ReviewRating, mode: ReviewMode, reviewedAt: Date, before: CardState, after: CardState) {
        self.entry = entry
        self.languageCode = entry.languageCode
        self.reviewedAt = reviewedAt
        self.ratingRaw = rating.rawValue
        self.modeRaw = mode.rawValue
        self.intervalBefore = before.intervalDays
        self.intervalAfter = after.intervalDays
        self.easeBefore = before.ease
        self.easeAfter = after.ease
        self.wasNew = before.isNew
        self.changedSchedule = before != after
    }

    public var rating: ReviewRating {
        ReviewRating(rawValue: ratingRaw) ?? .good
    }

    public var mode: ReviewMode {
        ReviewMode(rawValue: modeRaw) ?? .flashcard
    }
}
