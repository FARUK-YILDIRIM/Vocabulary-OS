import Foundation

/// When a study plan runs (SPEC C10): on some weekdays, at one time of day.
public struct PlanSchedule: Hashable, Codable, Sendable {
    /// `Calendar` weekdays: 1 is Sunday, 7 is Saturday.
    public private(set) var weekdays: Set<Int>
    public private(set) var hour: Int
    public private(set) var minute: Int

    public static let allWeekdays = Set(1...7)

    /// Weekdays outside 1…7 are dropped, and the time is clamped to a real hour and minute.
    public init(weekdays: Set<Int>, hour: Int, minute: Int) {
        self.weekdays = weekdays.intersection(Self.allWeekdays)
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// - Parameter weekdayBits: bit 0 for Sunday … bit 6 for Saturday (see `weekdayBits`).
    public init(weekdayBits: Int, hour: Int, minute: Int) {
        self.init(weekdays: Set(Self.allWeekdays.filter { weekdayBits & 1 << ($0 - 1) != 0 }), hour: hour, minute: minute)
    }

    /// The weekdays as bits for storage, bit 0 for Sunday.
    public var weekdayBits: Int {
        weekdays.reduce(0) { $0 | 1 << ($1 - 1) }
    }

    public var isEveryDay: Bool { weekdays == Self.allWeekdays }

    /// One weekly trigger per weekday, in weekday order, for `UNCalendarNotificationTrigger`.
    public var triggers: [DateComponents] {
        weekdays.sorted().map { DateComponents(hour: hour, minute: minute, weekday: $0) }
    }

    /// The next time the plan runs after `date`; `nil` without weekdays.
    public func nextDate(after date: Date, calendar: Calendar) -> Date? {
        triggers.compactMap { calendar.nextDate(after: date, matching: $0, matchingPolicy: .nextTime) }.min()
    }
}

/// The weekly reminders study plans need (SPEC C10): one per planned weekday. iOS keeps at most 64
/// pending notifications, so when plans need more, the ones due soonest are kept.
public enum PlanReminders {
    public static let limit = 64

    /// Every reminder's notification identifier starts with this, so the app's other notifications
    /// are left alone.
    public static let identifierPrefix = "plan."

    public struct Slot: Hashable, Sendable {
        public let planID: UUID
        /// Weekday, hour and minute, repeating weekly.
        public let trigger: DateComponents
        public let nextDate: Date

        /// Unique per plan and weekday, so a reminder is replaced rather than duplicated.
        public var identifier: String {
            "\(PlanReminders.identifierPrefix)\(planID.uuidString).\(trigger.weekday ?? 0)"
        }
    }

    /// The reminders for the plans, soonest first, at most `limit`.
    public static func slots(for plans: [UUID: PlanSchedule], after now: Date, calendar: Calendar, limit: Int = limit) -> [Slot] {
        let slots = plans.flatMap { id, schedule in
            schedule.triggers.compactMap { trigger in
                calendar.nextDate(after: now, matching: trigger, matchingPolicy: .nextTime).map {
                    Slot(planID: id, trigger: trigger, nextDate: $0)
                }
            }
        }
        // Ties are broken by identifier, so the same plans always give the same reminders.
        let sorted = slots.sorted { lhs, rhs in
            lhs.nextDate != rhs.nextDate ? lhs.nextDate < rhs.nextDate : lhs.identifier < rhs.identifier
        }
        return Array(sorted.prefix(max(0, limit)))
    }
}

/// Links into the app (`vocabularyos://…`): reminders open them, and so can other apps.
public enum DeepLink: Hashable, Sendable {
    /// Starts a study plan's activity: `vocabularyos://plan/<id>`.
    case plan(UUID)

    public static let scheme = "vocabularyos"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.host()?.lowercased() == "plan",
              let id = UUID(uuidString: url.lastPathComponent)
        else { return nil }
        self = .plan(id)
    }

    public var url: URL {
        switch self {
        case .plan(let id):
            // A fixed scheme and host with a UUID always make a valid URL.
            URL(string: "\(Self.scheme)://plan/\(id.uuidString)")!
        }
    }
}
