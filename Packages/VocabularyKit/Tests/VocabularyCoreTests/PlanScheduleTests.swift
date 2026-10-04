import Foundation
import Testing
@testable import VocabularyCore

@Suite struct PlanScheduleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    /// Sunday, October 4, 2026, 10:00 in Istanbul.
    private var sundayMorning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 10))!
    }

    private let monday = 2, wednesday = 4, friday = 6

    @Test func monWedFriAtEightGivesThreeWeeklyTriggers() {
        let schedule = PlanSchedule(weekdays: [friday, monday, wednesday], hour: 8, minute: 0)
        #expect(schedule.triggers == [
            DateComponents(hour: 8, minute: 0, weekday: monday),
            DateComponents(hour: 8, minute: 0, weekday: wednesday),
            DateComponents(hour: 8, minute: 0, weekday: friday),
        ])
        #expect(!schedule.isEveryDay)
    }

    @Test func dropsImpossibleDaysAndTimes() {
        let schedule = PlanSchedule(weekdays: [0, 1, 8], hour: 25, minute: -5)
        #expect(schedule.weekdays == [1])
        #expect(schedule.hour == 23)
        #expect(schedule.minute == 0)
    }

    @Test func storesWeekdaysAsBits() {
        let schedule = PlanSchedule(weekdays: [1, monday, 7], hour: 19, minute: 30)
        #expect(schedule.weekdayBits == 0b100_0011)
        #expect(PlanSchedule(weekdayBits: schedule.weekdayBits, hour: 19, minute: 30) == schedule)
        #expect(PlanSchedule(weekdays: PlanSchedule.allWeekdays, hour: 19, minute: 30).isEveryDay)
    }

    @Test func findsTheNextTime() {
        let schedule = PlanSchedule(weekdays: [monday, wednesday, friday], hour: 8, minute: 0)
        let next = schedule.nextDate(after: sundayMorning, calendar: calendar)
        #expect(next == calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8)))
        #expect(PlanSchedule(weekdays: [], hour: 8, minute: 0).nextDate(after: sundayMorning, calendar: calendar) == nil)
    }

    @Test func remindersComeOnePerPlannedDaySoonestFirst() {
        let quiz = UUID(), podcast = UUID()
        let slots = PlanReminders.slots(for: [
            quiz: PlanSchedule(weekdays: [monday, wednesday, friday], hour: 8, minute: 0),
            podcast: PlanSchedule(weekdays: [1], hour: 19, minute: 30),
        ], after: sundayMorning, calendar: calendar)

        #expect(slots.map(\.planID) == [podcast, quiz, quiz, quiz])
        #expect(slots.map(\.trigger.weekday) == [1, monday, wednesday, friday])
        #expect(slots.first?.nextDate == calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 19, minute: 30)))
        #expect(slots.first?.identifier == "plan.\(podcast.uuidString).1")
        #expect(Set(slots.map(\.identifier)).count == 4)
    }

    /// iOS keeps 64 pending notifications at most; the ones due soonest stay.
    @Test func capsRemindersAtSixtyFour() {
        var plans: [UUID: PlanSchedule] = [:]
        for hour in 8..<18 {
            plans[UUID()] = PlanSchedule(weekdays: PlanSchedule.allWeekdays, hour: hour, minute: 0)
        }
        let all = PlanReminders.slots(for: plans, after: sundayMorning, calendar: calendar, limit: .max)
        #expect(all.count == 70)

        let kept = PlanReminders.slots(for: plans, after: sundayMorning, calendar: calendar)
        #expect(PlanReminders.limit == 64)
        #expect(kept.count == 64)
        #expect(kept == Array(all.prefix(64)))
        #expect(kept.map(\.nextDate) == kept.map(\.nextDate).sorted())
    }

    @Test func readsPlanLinks() throws {
        let id = UUID()
        let link = DeepLink.plan(id)
        #expect(link.url.absoluteString == "vocabularyos://plan/\(id.uuidString)")
        #expect(DeepLink(url: link.url) == link)
        #expect(DeepLink(url: try #require(URL(string: "VocabularyOS://plan/\(id.uuidString.lowercased())"))) == link)
        #expect(DeepLink(url: try #require(URL(string: "vocabularyos://plan/not-an-id"))) == nil)
        #expect(DeepLink(url: try #require(URL(string: "vocabularyos://word/\(id.uuidString)"))) == nil)
        #expect(DeepLink(url: try #require(URL(string: "https://example.com/plan/\(id.uuidString)"))) == nil)
    }
}
