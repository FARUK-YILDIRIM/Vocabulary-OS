import Observation
import VocabularyData

/// Where the app goes next. Plan links and reminders set it; the screen that runs the activity
/// takes the plan, so it starts once.
@Observable
final class AppNavigation {
    var tab: AppTab
    /// A plan whose activity should start.
    private(set) var startingPlan: StudyPlan?

    init(tab: AppTab) {
        self.tab = tab
    }

    /// Shows the plan's tab; Today runs reviews, Practice runs quizzes and podcasts.
    func start(_ plan: StudyPlan) {
        tab = plan.activity == .review ? .today : .practice
        startingPlan = plan
    }

    /// The starting plan, if it runs one of these activities; it is then no longer pending.
    func takePlan(for activities: Set<PlanActivity>) -> StudyPlan? {
        guard let plan = startingPlan, activities.contains(plan.activity) else { return nil }
        startingPlan = nil
        return plan
    }
}
