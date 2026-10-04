import Foundation
import os
import UserNotifications
import VocabularyCore

/// What the scheduler needs from the notification center; tests use a fake.
@MainActor
public protocol PlanNotificationCenter: AnyObject {
    func pendingRequestIdentifiers() async -> [String]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
    /// Whether the learner allows notifications.
    func canNotify() async -> Bool
}

/// The system's notification center.
@MainActor
public final class SystemNotificationCenter: PlanNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    public init() {}

    public func pendingRequestIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func canNotify() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: true
        default: false
        }
    }
}

/// A reminder's text, written by the app in the learner's language.
public struct PlanReminderText: Sendable, Hashable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// Keeps the pending reminders in line with the study plans (SPEC C10): a weekly reminder for each
/// planned weekday of every plan that is on, the soonest 64 when there are more. Each device runs it
/// with the synced plans. A reminder opens `vocabularyos://plan/<id>`, which starts the plan.
@MainActor
public final class PlanNotificationScheduler {
    /// The reminder's link, under this `userInfo` key.
    nonisolated public static let urlKey = "url"

    private let center: any PlanNotificationCenter
    private var running: Task<Void, Never>?
    private let logger = Logger(subsystem: VocabularyCore.logSubsystem, category: VocabularyData.logCategory)

    public init(center: any PlanNotificationCenter) {
        self.center = center
    }

    /// Removes reminders no plan needs any more and adds the ones they need. Runs one at a time, so a
    /// reconcile started for older plans can't add back what a newer one removed.
    public func reconcile(_ plans: [StudyPlan], now: Date = .now, calendar: Calendar = .current, text: (StudyPlan) -> PlanReminderText) async {
        let requests = Self.requests(for: plans, now: now, calendar: calendar, text: text)
        let previous = running
        let task = Task {
            await previous?.value
            await apply(requests)
        }
        running = task
        await task.value
    }

    private func apply(_ requests: [UNNotificationRequest]) async {
        let wanted = Set(requests.map(\.identifier))
        let stale = await center.pendingRequestIdentifiers().filter {
            $0.hasPrefix(PlanReminders.identifierPrefix) && !wanted.contains($0)
        }
        center.removePendingRequests(withIdentifiers: stale)
        guard await center.canNotify() else { return }
        // Adding a request with an existing identifier replaces it, which also updates its text.
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                logger.error("Could not schedule a plan reminder: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func requests(for plans: [StudyPlan], now: Date, calendar: Calendar, text: (StudyPlan) -> PlanReminderText) -> [UNNotificationRequest] {
        let enabled = plans.filter(\.isEnabled)
        // Sync can briefly leave two copies of a plan; one reminder each is enough.
        let byID = Dictionary(enabled.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let slots = PlanReminders.slots(for: byID.mapValues(\.schedule), after: now, calendar: calendar)
        var texts: [UUID: PlanReminderText] = [:]
        return slots.compactMap { slot in
            guard let plan = byID[slot.planID] else { return nil }
            let reminder = texts[slot.planID] ?? text(plan)
            texts[slot.planID] = reminder
            let trigger = UNCalendarNotificationTrigger(dateMatching: slot.trigger, repeats: true)
            return UNNotificationRequest(identifier: slot.identifier, content: content(for: plan, text: reminder), trigger: trigger)
        }
    }

    /// A plan's reminder, which opens the plan's link when tapped.
    public static func content(for plan: StudyPlan, text: PlanReminderText) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.threadIdentifier = "plans"
        content.userInfo = [urlKey: DeepLink.plan(plan.id).url.absoluteString]
        return content
    }
}
