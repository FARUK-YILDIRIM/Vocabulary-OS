import Foundation

/// Today's reviews for one language (ADR-007): due words first, the most overdue first, then new
/// words in the order they were captured, within the daily limits. A word answered Again comes back
/// later in the same session.
public struct DailyQueue: Sendable {
    /// A word's review state, as the queue needs it.
    public struct Card: Sendable, Hashable {
        public var id: UUID
        public var state: CardState
        public var createdAt: Date

        public init(id: UUID, state: CardState, createdAt: Date) {
            self.id = id
            self.state = state
            self.createdAt = createdAt
        }
    }

    /// Reviews and new words already done today, which count against the limits.
    public struct Progress: Sendable, Hashable {
        public var reviews: Int
        public var newWords: Int

        public init(reviews: Int = 0, newWords: Int = 0) {
            self.reviews = reviews
            self.newWords = newWords
        }
    }

    /// How many other words come before a word answered Again shows again.
    public static let requeueGap = 3

    /// The words still to show, in order.
    public private(set) var remaining: [UUID]
    /// Due words in today's queue.
    public let reviewCount: Int
    /// New words in today's queue.
    public let newCount: Int

    public init(cards: [Card], limits: ReviewLimits, done: Progress = Progress(), now: Date) {
        let reviews = cards
            .filter { !$0.state.isNew && $0.state.isDue(at: now) }
            .sorted { ($0.state.dueAt, $0.createdAt, $0.id.uuidString) < ($1.state.dueAt, $1.createdAt, $1.id.uuidString) }
            .prefix(max(0, limits.reviewsPerDay - done.reviews))
        let newWords = cards
            .filter(\.state.isNew)
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            .prefix(max(0, limits.newPerDay - done.newWords))
        remaining = reviews.map(\.id) + newWords.map(\.id)
        reviewCount = reviews.count
        newCount = newWords.count
    }

    /// The word to show now.
    public var current: UUID? { remaining.first }

    public var isFinished: Bool { remaining.isEmpty }

    /// Moves past the current word; after Again it comes back a few words later.
    public mutating func answer(_ rating: ReviewRating) {
        guard !remaining.isEmpty else { return }
        let card = remaining.removeFirst()
        if rating == .again {
            remaining.insert(card, at: min(Self.requeueGap, remaining.count))
        }
    }
}
