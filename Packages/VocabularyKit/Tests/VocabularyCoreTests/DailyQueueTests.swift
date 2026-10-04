import Foundation
import Testing
@testable import VocabularyCore

@Suite struct DailyQueueTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func card(_ id: Int, dueDaysAgo: Int? = nil, createdHoursAgo: Double = 1) -> DailyQueue.Card {
        let state: CardState
        if let dueDaysAgo {
            state = CardState(
                intervalDays: 3,
                repetitions: 2,
                dueAt: now.addingTimeInterval(Double(-dueDaysAgo) * 86_400),
                lastReviewedAt: now.addingTimeInterval(-10 * 86_400)
            )
        } else {
            state = CardState()
        }
        return DailyQueue.Card(id: Self.id(id), state: state, createdAt: now.addingTimeInterval(-createdHoursAgo * 3_600))
    }

    private static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    @Test func reviewsComeFirstMostOverdueFirstThenNewWordsOldestFirst() {
        let queue = DailyQueue(cards: [
            card(1, createdHoursAgo: 1),
            card(2, dueDaysAgo: 1),
            card(3, createdHoursAgo: 5),
            card(4, dueDaysAgo: 4),
        ], limits: ReviewLimits(), now: now)

        #expect(queue.remaining == [4, 2, 3, 1].map(Self.id))
        #expect(queue.reviewCount == 2)
        #expect(queue.newCount == 2)
    }

    @Test func cardsNotYetDueStayOut() {
        let future = DailyQueue.Card(
            id: Self.id(9),
            state: CardState(intervalDays: 6, repetitions: 2, dueAt: now.addingTimeInterval(86_400), lastReviewedAt: now),
            createdAt: now
        )
        let queue = DailyQueue(cards: [future, card(1, dueDaysAgo: 0)], limits: ReviewLimits(), now: now)
        #expect(queue.remaining == [Self.id(1)])
    }

    @Test func dailyLimitsCountWhatWasAlreadyDoneToday() {
        let cards = (1...10).map { card($0, createdHoursAgo: Double($0)) } + (11...20).map { card($0, dueDaysAgo: $0) }
        let queue = DailyQueue(
            cards: cards,
            limits: ReviewLimits(newPerDay: 5, reviewsPerDay: 8),
            done: DailyQueue.Progress(reviews: 6, newWords: 3),
            now: now
        )
        #expect(queue.reviewCount == 2)
        #expect(queue.newCount == 2)
        #expect(queue.remaining.count == 4)
    }

    @Test func aCardAnsweredAgainComesBackLaterInTheSession() {
        var queue = DailyQueue(cards: (1...6).map { card($0, dueDaysAgo: 7 - $0) }, limits: ReviewLimits(), now: now)
        let first = queue.current
        queue.answer(.again)
        #expect(queue.current != first)
        #expect(queue.remaining.count == 6)
        #expect(queue.remaining.firstIndex(of: first!) == DailyQueue.requeueGap)

        // With fewer cards left than the gap, it comes back at the end.
        var short = DailyQueue(cards: [card(1, dueDaysAgo: 2), card(2, dueDaysAgo: 1)], limits: ReviewLimits(), now: now)
        short.answer(.again)
        #expect(short.remaining == [Self.id(2), Self.id(1)])
    }

    @Test func otherRatingsFinishTheCard() {
        var queue = DailyQueue(cards: [card(1, dueDaysAgo: 1), card(2)], limits: ReviewLimits(), now: now)
        queue.answer(.good)
        queue.answer(.hard)
        #expect(queue.isFinished)
        #expect(queue.current == nil)
        queue.answer(.easy)
        #expect(queue.isFinished)
    }
}
