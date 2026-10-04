import Foundation
import SwiftData
import VocabularyCore

/// What a study plan starts (SPEC C10).
public enum PlanActivity: String, CaseIterable, Codable, Sendable {
    /// Flashcards for the words due that day.
    case review
    case quiz
    case podcast
}

/// A recurring study session (SPEC C10): an activity in one language, on some weekdays at a time of
/// day. Plans sync; every device schedules its own reminders from them.
///
/// CloudKit rules (ADR-002): every property has a default.
@Model
public final class StudyPlan {
    public var id: UUID = UUID()
    public var activityRaw: String = PlanActivity.review.rawValue
    public var languageCode: String = ""
    /// `PlanSchedule.weekdayBits`: bit 0 for Sunday.
    public var weekdayBits: Int = 0
    public var hour: Int = 8
    public var minute: Int = 0
    /// A plan that is off keeps its settings but sends no reminders.
    public var isEnabled: Bool = true
    /// Quiz: `QuizSource` as JSON, and how many questions.
    public var quizSourceData: Data?
    public var quizLength: Int = 10
    public var podcastLevelRaw: String = LanguageLevel.a2.rawValue
    public var podcastLengthRaw: String = PodcastLength.short.rawValue
    public var podcastStyleRaw: String = PodcastStyle.dialogue.rawValue
    public var createdAt: Date = Date.now

    public init(activity: PlanActivity, language: LanguageCode, schedule: PlanSchedule) {
        self.activityRaw = activity.rawValue
        self.languageCode = language.rawValue
        self.schedule = schedule
    }

    public var activity: PlanActivity {
        get { PlanActivity(rawValue: activityRaw) ?? .review }
        set { activityRaw = newValue.rawValue }
    }

    public var language: LanguageCode? {
        get { LanguageCode(rawValue: languageCode) }
        set { languageCode = newValue?.rawValue ?? "" }
    }

    public var schedule: PlanSchedule {
        get { PlanSchedule(weekdayBits: weekdayBits, hour: hour, minute: minute) }
        set {
            weekdayBits = newValue.weekdayBits
            hour = newValue.hour
            minute = newValue.minute
        }
    }

    public var quizSource: QuizSource {
        get { quizSourceData.flatMap { try? JSONDecoder().decode(QuizSource.self, from: $0) } ?? .due }
        set { quizSourceData = try? JSONEncoder().encode(newValue) }
    }

    public var podcastLevel: LanguageLevel {
        get { LanguageLevel(rawValue: podcastLevelRaw) ?? .a2 }
        set { podcastLevelRaw = newValue.rawValue }
    }

    public var podcastLength: PodcastLength {
        get { PodcastLength(rawValue: podcastLengthRaw) ?? .short }
        set { podcastLengthRaw = newValue.rawValue }
    }

    public var podcastStyle: PodcastStyle {
        get { PodcastStyle(rawValue: podcastStyleRaw) ?? .dialogue }
        set { podcastStyleRaw = newValue.rawValue }
    }
}

/// Study plans in the store (SPEC C10).
@MainActor
public final class PlanRepository {
    private let words: WordRepository
    private var context: ModelContext { words.context }

    public init(words: WordRepository) {
        self.words = words
    }

    /// Every plan, oldest first.
    public func plans() throws -> [StudyPlan] {
        try context.fetch(FetchDescriptor<StudyPlan>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    public func plan(id: UUID) throws -> StudyPlan? {
        var descriptor = FetchDescriptor<StudyPlan>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func insert(_ plan: StudyPlan) throws {
        context.insert(plan)
        try context.save()
    }

    /// Saves changes made to plans.
    public func save() throws {
        try context.save()
    }

    public func delete(_ plan: StudyPlan) throws {
        context.delete(plan)
        try context.save()
    }
}
