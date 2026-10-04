import Foundation

/// The learner's answer to a review, with its SM-2 quality (ADR-007).
public enum ReviewRating: String, CaseIterable, Codable, Sendable {
    case again, hard, good, easy

    /// SM-2 quality q: Again 2, Hard 3, Good 4, Easy 5.
    public var quality: Int {
        switch self {
        case .again: 2
        case .hard: 3
        case .good: 4
        case .easy: 5
        }
    }

    /// The SM-2 ease change, 0.1 − (5 − q)(0.08 + (5 − q) · 0.02), in hundredths.
    public var easeDelta: Double {
        let missing = Double(5 - quality)
        return Self.hundredths(0.1 - missing * (0.08 + missing * 0.02))
    }

    /// Ease values and changes are whole hundredths; rounding drops floating-point drift.
    static func hundredths(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

/// One SM-2 review step (ADR-007). Pure value logic: the same input always gives the same output.
public struct ReviewScheduler: Sendable {
    public var minimumEase = 1.3

    public init() {}

    /// The card after the learner's answer. Only the first answer of a calendar day moves the
    /// schedule; later answers that day, such as a re-queued card or a quiz, leave it unchanged.
    public func schedule(_ card: CardState, rating: ReviewRating, now: Date, calendar: Calendar) -> CardState {
        guard !card.wasReviewed(on: now, calendar: calendar) else { return card }
        var next = card
        if rating == .again {
            next.repetitions = 0
            next.lapses += 1
            next.intervalDays = 1
        } else {
            next.repetitions += 1
            next.intervalDays = switch next.repetitions {
            case 1: 1
            case 2: 6
            // The ease from before this review, as in SM-2.
            default: max(1, Int((Double(card.intervalDays) * card.ease).rounded()))
            }
        }
        next.ease = ReviewRating.hundredths(max(minimumEase, card.ease + rating.easeDelta))
        let today = calendar.startOfDay(for: now)
        next.dueAt = calendar.date(byAdding: .day, value: next.intervalDays, to: today) ?? today
        next.lastReviewedAt = now
        return next
    }
}
