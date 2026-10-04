import Foundation
import Testing
import UserNotifications
import VocabularyCore
@testable import VocabularyData

@MainActor
@Suite struct StudyPlanTests {
    private let plans: PlanRepository
    private let center = FakeNotificationCenter()
    private let calendar: Calendar
    private let now: Date
    private let monday = 2, tuesday = 3, wednesday = 4, thursday = 5, friday = 6

    init() throws {
        plans = PlanRepository(words: WordRepository(container: try VocabularyStore.makeContainer(inMemory: true, cloudSync: false)))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 10))!
    }

    private func makePlan(_ activity: PlanActivity = .quiz, weekdays: Set<Int>, hour: Int = 8, minute: Int = 0) throws -> StudyPlan {
        let plan = StudyPlan(activity: activity, language: .german, schedule: PlanSchedule(weekdays: weekdays, hour: hour, minute: minute))
        try plans.insert(plan)
        return plan
    }

    private func reconcile() async throws {
        await PlanNotificationScheduler(center: center).reconcile(try plans.plans(), now: now, calendar: calendar) { plan in
            PlanReminderText(title: "\(plan.activity.rawValue) \(plan.languageCode)", body: "Tap to start.")
        }
    }

    /// Weekday, hour and minute of each pending plan reminder, sorted.
    private var pendingTriggers: [[Int?]] {
        center.requests.values
            .filter { $0.identifier.hasPrefix(PlanReminders.identifierPrefix) }
            .compactMap { $0.trigger as? UNCalendarNotificationTrigger }
            .map { [$0.dateComponents.weekday, $0.dateComponents.hour, $0.dateComponents.minute] }
            .sorted { ($0[0] ?? 0, $0[1] ?? 0) < ($1[0] ?? 0, $1[1] ?? 0) }
    }

    @Test func storesAPlanWithItsOptions() throws {
        let plan = try makePlan(weekdays: [monday, wednesday, friday])
        plan.quizSource = .favorites
        plan.quizLength = 5
        plan.podcastLevel = .b1
        try plans.save()

        let stored = try #require(try plans.plan(id: plan.id))
        #expect(stored.activity == .quiz)
        #expect(stored.language == .german)
        #expect(stored.schedule == PlanSchedule(weekdays: [monday, wednesday, friday], hour: 8, minute: 0))
        #expect(stored.quizSource == .favorites)
        #expect(stored.quizLength == 5)
        #expect(stored.podcastLevel == .b1)
        #expect(stored.isEnabled)
        #expect(try plans.plan(id: UUID()) == nil)
    }

    @Test func remindsMonWedFriAtEightEveryWeek() async throws {
        let plan = try makePlan(weekdays: [monday, wednesday, friday])
        try await reconcile()

        #expect(pendingTriggers == [[monday, 8, 0], [wednesday, 8, 0], [friday, 8, 0]])
        let requests = Array(center.requests.values)
        #expect(requests.allSatisfy { ($0.trigger as? UNCalendarNotificationTrigger)?.repeats == true })
        #expect(requests.allSatisfy { $0.content.title == "quiz de" && $0.content.body == "Tap to start." })
        #expect(requests.allSatisfy { $0.content.userInfo["url"] as? String == DeepLink.plan(plan.id).url.absoluteString })
    }

    @Test func editingAPlanReplacesItsReminders() async throws {
        let plan = try makePlan(weekdays: [monday, wednesday, friday])
        try await reconcile()
        plan.schedule = PlanSchedule(weekdays: [tuesday, thursday], hour: 19, minute: 30)
        try plans.save()
        try await reconcile()

        #expect(pendingTriggers == [[tuesday, 19, 30], [thursday, 19, 30]])
    }

    @Test func turningOffOrDeletingAPlanRemovesItsReminders() async throws {
        center.requests["other"] = UNNotificationRequest(identifier: "other", content: UNMutableNotificationContent(), trigger: nil)
        let quiz = try makePlan(weekdays: [monday])
        let podcast = try makePlan(.podcast, weekdays: [friday], hour: 19)
        try await reconcile()
        #expect(pendingTriggers == [[monday, 8, 0], [friday, 19, 0]])

        quiz.isEnabled = false
        try plans.save()
        try await reconcile()
        #expect(pendingTriggers == [[friday, 19, 0]])

        try plans.delete(podcast)
        try await reconcile()
        #expect(pendingTriggers.isEmpty)
        #expect(center.requests["other"] != nil, "Other notifications are left alone")
    }

    @Test func keepsTheSoonestSixtyFourReminders() async throws {
        for hour in 8..<18 {
            _ = try makePlan(weekdays: PlanSchedule.allWeekdays, hour: hour)
        }
        try await reconcile()
        #expect(center.requests.count == 64)
        // From Sunday 10:00, the six latest are left out: Saturday 15:00 to 17:00, and next Sunday's
        // 08:00 to 10:00.
        for dropped in [[7, 15, 0], [7, 16, 0], [7, 17, 0], [1, 8, 0], [1, 9, 0], [1, 10, 0]] {
            #expect(!pendingTriggers.contains(dropped))
        }
        #expect(pendingTriggers.contains([1, 11, 0]))
        #expect(pendingTriggers.contains([7, 14, 0]))
    }

    @Test func addsNoRemindersWithoutPermission() async throws {
        _ = try makePlan(weekdays: [monday])
        try await reconcile()
        center.isAllowed = false
        _ = try makePlan(weekdays: [friday])
        try plans.delete(try #require(try plans.plans().first))
        try await reconcile()

        #expect(center.requests.isEmpty, "The deleted plan's reminder is removed; the new one isn't added")
    }
}

/// Keeps requests in memory instead of scheduling them.
@MainActor
final class FakeNotificationCenter: PlanNotificationCenter {
    var requests: [String: UNNotificationRequest] = [:]
    var isAllowed = true

    func pendingRequestIdentifiers() async -> [String] {
        Array(requests.keys)
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests[request.identifier] = request
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        for identifier in identifiers {
            requests[identifier] = nil
        }
    }

    func canNotify() async -> Bool {
        isAllowed
    }
}
