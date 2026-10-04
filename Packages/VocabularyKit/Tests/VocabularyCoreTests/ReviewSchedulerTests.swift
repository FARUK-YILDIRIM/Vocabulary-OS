import Foundation
import Testing
@testable import VocabularyCore

@Suite struct ReviewSchedulerTests {
    private let scheduler = ReviewScheduler()

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func date(_ text: String, _ zone: String = "Europe/Istanbul") -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    /// Reviews a new card once a day with the given ratings and returns each resulting state.
    private func run(_ ratings: [ReviewRating], from card: CardState = CardState()) -> [CardState] {
        let calendar = Self.calendar("Europe/Istanbul")
        var states: [CardState] = []
        var current = card
        var now = Self.date("2026-10-01 09:00")
        for rating in ratings {
            current = scheduler.schedule(current, rating: rating, now: now, calendar: calendar)
            states.append(current)
            now = calendar.date(byAdding: .day, value: 1, to: now)!
        }
        return states
    }

    // MARK: Ratings

    @Test func easeChangesFollowSM2() {
        #expect(ReviewRating.again.easeDelta == -0.32)
        #expect(ReviewRating.hard.easeDelta == -0.14)
        #expect(ReviewRating.good.easeDelta == 0)
        #expect(ReviewRating.easy.easeDelta == 0.1)
        #expect(ReviewRating.allCases.map(\.quality) == [2, 3, 4, 5])
    }

    struct Sequence: Sendable, CustomTestStringConvertible {
        let ratings: [ReviewRating]
        let intervals: [Int]
        let eases: [Double]
        var testDescription: String { ratings.map { "\($0)" }.joined(separator: ",") }
    }

    @Test(arguments: [
        Sequence(ratings: [.good, .good, .good, .good], intervals: [1, 6, 15, 38], eases: [2.5, 2.5, 2.5, 2.5]),
        Sequence(ratings: [.easy, .easy, .easy], intervals: [1, 6, 16], eases: [2.6, 2.7, 2.8]),
        Sequence(ratings: [.hard, .hard, .hard], intervals: [1, 6, 13], eases: [2.36, 2.22, 2.08]),
        Sequence(ratings: [.good, .good, .easy, .good], intervals: [1, 6, 15, 39], eases: [2.5, 2.5, 2.6, 2.6]),
        Sequence(ratings: [.good, .hard, .good], intervals: [1, 6, 14], eases: [2.5, 2.36, 2.36]),
    ])
    func ratingSequencesGrowTheInterval(_ sequence: Sequence) {
        let states = run(sequence.ratings)
        #expect(states.map(\.intervalDays) == sequence.intervals)
        #expect(states.map(\.ease) == sequence.eases)
        #expect(states.last?.repetitions == sequence.ratings.count)
        #expect(states.allSatisfy { $0.lapses == 0 })
    }

    @Test func aLapseRestartsTheIntervalsButKeepsTheLowerEase() {
        let states = run([.good, .good, .good, .again, .good, .good, .good])
        #expect(states.map(\.intervalDays) == [1, 6, 15, 1, 1, 6, 13])
        #expect(states.map(\.repetitions) == [1, 2, 3, 0, 1, 2, 3])
        #expect(states.map(\.lapses) == [0, 0, 0, 1, 1, 1, 1])
        #expect(states[3].ease == 2.18)
    }

    @Test func easeNeverFallsBelowTheFloor() {
        let states = run(Array(repeating: .again, count: 6))
        #expect(states.map(\.ease) == [2.18, 1.86, 1.54, 1.3, 1.3, 1.3])
        #expect(states.last?.lapses == 6)
        #expect(states.allSatisfy { $0.intervalDays == 1 })
    }

    @Test(arguments: [
        // interval × ease before the review → rounded half away from zero
        (6, 2.25, 14),
        (6, 2.08, 12),
        (10, 1.35, 14),
        (1, 1.3, 1),
    ])
    func longerIntervalsRoundToWholeDays(interval: Int, ease: Double, expected: Int) {
        let card = CardState(ease: ease, intervalDays: interval, repetitions: 2, lastReviewedAt: Self.date("2026-09-01 09:00"))
        let next = scheduler.schedule(card, rating: .good, now: Self.date("2026-10-01 09:00"), calendar: Self.calendar("Europe/Istanbul"))
        #expect(next.intervalDays == expected)
    }

    // MARK: Days

    @Test func theCardIsDueAtTheStartOfTheDayInTheLearnersTimeZone() {
        let now = Self.date("2026-10-01 23:30")
        let next = scheduler.schedule(CardState(), rating: .good, now: now, calendar: Self.calendar("Europe/Istanbul"))
        #expect(next.dueAt == Self.date("2026-10-02 00:00"))
        #expect(next.lastReviewedAt == now)
        #expect(next.isDue(at: Self.date("2026-10-02 00:00")))
        #expect(!next.isDue(at: Self.date("2026-10-01 23:59")))
    }

    @Test func theSameMomentIsADifferentDayInAnotherTimeZone() {
        // 23:30 in Istanbul is 13:30 in Los Angeles, on the same date there too.
        let now = Self.date("2026-10-01 23:30")
        let istanbul = scheduler.schedule(CardState(), rating: .good, now: now, calendar: Self.calendar("Europe/Istanbul"))
        let losAngeles = scheduler.schedule(CardState(), rating: .good, now: now, calendar: Self.calendar("America/Los_Angeles"))
        #expect(istanbul.dueAt == Self.date("2026-10-02 00:00"))
        #expect(losAngeles.dueAt == Self.date("2026-10-02 00:00", "America/Los_Angeles"))
    }

    @Test func dueDatesStayAtMidnightAcrossDaylightSavingChanges() {
        // Clocks in New York go forward on 8 March 2026, so that day has 23 hours.
        let calendar = Self.calendar("America/New_York")
        let card = CardState(ease: 2.5, intervalDays: 1, repetitions: 1, lastReviewedAt: Self.date("2026-03-06 20:00", "America/New_York"))
        let next = scheduler.schedule(card, rating: .good, now: Self.date("2026-03-07 20:00", "America/New_York"), calendar: calendar)
        #expect(next.intervalDays == 6)
        #expect(next.dueAt == Self.date("2026-03-13 00:00", "America/New_York"))
    }

    @Test func onlyTheFirstReviewOfTheDayMovesTheSchedule() {
        let calendar = Self.calendar("Europe/Istanbul")
        let morning = scheduler.schedule(CardState(), rating: .again, now: Self.date("2026-10-01 09:00"), calendar: calendar)
        // The re-queued card answered later the same day, and a quiz answer in the evening.
        let afternoon = scheduler.schedule(morning, rating: .good, now: Self.date("2026-10-01 15:00"), calendar: calendar)
        let evening = scheduler.schedule(afternoon, rating: .easy, now: Self.date("2026-10-01 23:59"), calendar: calendar)
        #expect(afternoon == morning)
        #expect(evening == morning)

        let nextDay = scheduler.schedule(evening, rating: .good, now: Self.date("2026-10-02 00:01"), calendar: calendar)
        #expect(nextDay.repetitions == 1)
        #expect(nextDay.lastReviewedAt == Self.date("2026-10-02 00:01"))
    }

    @Test func scheduleChangedTodayTellsWhetherAnAnswerStillCounts() {
        let calendar = Self.calendar("Europe/Istanbul")
        let reviewed = scheduler.schedule(CardState(), rating: .good, now: Self.date("2026-10-01 09:00"), calendar: calendar)
        #expect(!CardState().wasReviewed(on: Self.date("2026-10-01 10:00"), calendar: calendar))
        #expect(reviewed.wasReviewed(on: Self.date("2026-10-01 10:00"), calendar: calendar))
        #expect(!reviewed.wasReviewed(on: Self.date("2026-10-02 10:00"), calendar: calendar))
    }
}
