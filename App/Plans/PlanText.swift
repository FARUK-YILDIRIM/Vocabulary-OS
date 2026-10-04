import Foundation
import VocabularyCore
import VocabularyData

/// How plans read in lists and reminders, in the learner's language (SPEC C10).
enum PlanText {
    /// "Quiz · German".
    static func title(for plan: StudyPlan) -> String {
        title(activity: plan.activity, language: plan.language)
    }

    static func title(activity: PlanActivity, language: LanguageCode?) -> String {
        [String(localized: activity.title), language?.localizedName() ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// "Every day at 19:30", or "Mon, Wed, Fri at 08:00" with the week starting where the locale
    /// starts it.
    static func schedule(_ schedule: PlanSchedule, calendar: Calendar = .current) -> String {
        let time = calendar.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: .now)?
            .formatted(date: .omitted, time: .shortened) ?? ""
        if schedule.isEveryDay {
            return String(localized: "Every day at \(time)")
        }
        let days = weekdays(calendar: calendar)
            .filter(schedule.weekdays.contains)
            .map { calendar.shortStandaloneWeekdaySymbols[$0 - 1] }
            .formatted(.list(type: .and, width: .narrow))
        return String(localized: "\(days) at \(time)")
    }

    /// The week's days in the locale's order, as `Calendar` weekdays (1 is Sunday).
    static func weekdays(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// The reminder: the plan's title, and what tapping it starts.
    static func reminder(for plan: StudyPlan) -> PlanReminderText {
        let body = switch plan.activity {
        case .review: String(localized: "Tap to review the words due today.")
        // Grammar agreement ("1 question", "5 questions") needs an attributed string.
        case .quiz: String(AttributedString(localized: "Tap to start: ^[\(plan.quizLength) question](inflect: true) on your words.").characters)
        case .podcast: String(localized: "Tap to make a new episode with your words.")
        }
        return PlanReminderText(title: title(for: plan), body: body)
    }
}

extension PlanActivity {
    var title: LocalizedStringResource {
        switch self {
        case .review: "Review"
        case .quiz: "Quiz"
        case .podcast: "Podcast"
        }
    }

    var systemImage: String {
        switch self {
        case .review: "rectangle.on.rectangle.angled"
        case .quiz: "checklist"
        case .podcast: "waveform"
        }
    }
}
