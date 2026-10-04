import SwiftData
import SwiftUI
import VocabularyCore
import VocabularyData
#if os(iOS)
import UIKit
#endif

/// The Practice form's study plans: reminders that start a review, a quiz or a podcast (SPEC C10).
/// The form presents the editor, since presentations attached to a section don't show.
struct PlansSection: View {
    @Binding var draft: PlanDraft?
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \StudyPlan.createdAt) private var plans: [StudyPlan]
    @State private var remindersDenied = false

    var body: some View {
        let learning = Set(app.settings.profile?.learning ?? [])
        let visible = plans.filter { $0.language.map(learning.contains) == true }
        let isMissingReminders = remindersDenied && visible.contains(where: \.isEnabled)
        Section {
            ForEach(visible) { plan in
                Button {
                    draft = PlanDraft(plan: plan)
                } label: {
                    PlanRow(plan: plan)
                }
                .accessibilityIdentifier("plan-row")
            }
            Button {
                draft = PlanDraft(language: app.settings.profile?.learning.first)
            } label: {
                Label("New Plan", systemImage: "calendar.badge.plus")
            }
            .accessibilityIdentifier("practice-new-plan")
            if isMissingReminders {
                Button("Turn On Notifications", action: openNotificationSettings)
            }
        } header: {
            Text("Plans")
        } footer: {
            if isMissingReminders {
                Text("Notifications are off for Vocabulary-OS, so plans can't remind you.")
            } else {
                Text("A reminder at the times you choose; tapping it starts the activity.")
            }
        }
        .task(id: scenePhase) {
            remindersDenied = await app.remindersAreDenied()
        }
    }

    private func openNotificationSettings() {
        #if os(iOS)
        let settings = UIApplication.openNotificationSettingsURLString
        #else
        let settings = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        #endif
        if let url = URL(string: settings) {
            openURL(url)
        }
    }
}

/// A plan's activity, language and times.
private struct PlanRow: View {
    let plan: StudyPlan

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: plan.activity.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24)
            // Concrete colors: inside a button, `.primary` would be the button's tint.
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: PlanText.title(for: plan))
                    .foregroundStyle(Color.primary)
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        let schedule = PlanText.schedule(plan.schedule)
        return plan.isEnabled ? schedule : [schedule, String(localized: "Off")].joined(separator: " · ")
    }
}

/// A plan being edited; the store changes only on Save.
struct PlanDraft: Identifiable {
    let id = UUID()
    /// The plan being edited, `nil` for a new one.
    let planID: UUID?
    var activity: PlanActivity
    var language: LanguageCode?
    var weekdays: Set<Int>
    var time: Date
    var isEnabled: Bool
    var quizSource: QuizSource
    var quizLength: Int
    var podcastLevel: LanguageLevel
    var podcastLength: PodcastLength
    var podcastStyle: PodcastStyle

    /// A new plan: a quiz every day at 08:00.
    init(language: LanguageCode?, calendar: Calendar = .current) {
        planID = nil
        activity = .quiz
        self.language = language
        weekdays = PlanSchedule.allWeekdays
        time = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
        isEnabled = true
        quizSource = .due
        quizLength = 10
        podcastLevel = .a2
        podcastLength = .short
        podcastStyle = .dialogue
    }

    init(plan: StudyPlan, calendar: Calendar = .current) {
        planID = plan.id
        activity = plan.activity
        language = plan.language
        weekdays = plan.schedule.weekdays
        time = calendar.date(bySettingHour: plan.schedule.hour, minute: plan.schedule.minute, second: 0, of: .now) ?? .now
        isEnabled = plan.isEnabled
        quizSource = plan.quizSource
        quizLength = plan.quizLength
        podcastLevel = plan.podcastLevel
        podcastLength = plan.podcastLength
        podcastStyle = plan.podcastStyle
    }

    var schedule: PlanSchedule {
        let time = Calendar.current.dateComponents([.hour, .minute], from: time)
        return PlanSchedule(weekdays: weekdays, hour: time.hour ?? 8, minute: time.minute ?? 0)
    }

    func apply(to plan: StudyPlan) {
        plan.activity = activity
        plan.language = language
        plan.schedule = schedule
        plan.isEnabled = isEnabled
        plan.quizSource = quizSource
        plan.quizLength = quizLength
        plan.podcastLevel = podcastLevel
        plan.podcastLength = podcastLength
        plan.podcastStyle = podcastStyle
    }
}

/// Creates or edits a study plan (SPEC C10). Saving updates this device's reminders; the plan
/// syncs, and every other device schedules its own.
struct PlanEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlanDraft
    @State private var lists: [WordList] = []
    @State private var errorMessage: String?
    @State private var isConfirmingDelete = false

    init(draft: PlanDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activity", selection: $draft.activity) {
                        ForEach(PlanActivity.allCases, id: \.self) { activity in
                            Text(activity.title).tag(activity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("plan-activity")
                    Picker("Language", selection: $draft.language) {
                        ForEach(app.settings.profile?.learning ?? [], id: \.self) { code in
                            Text(verbatim: code.localizedName()).tag(Optional(code))
                        }
                    }
                    .accessibilityIdentifier("plan-language")
                } footer: {
                    switch draft.activity {
                    case .review: Text("Flashcards for the words due that day.")
                    case .quiz: Text("A quiz on your words; every answer counts as a review.")
                    case .podcast: Text("A new episode with your words; writing starts when you open the reminder.")
                    }
                }

                switch draft.activity {
                case .review:
                    EmptyView()
                case .quiz:
                    Section {
                        Picker("Words", selection: $draft.quizSource) {
                            Text("Due").tag(QuizSource.due)
                            Text("Recent").tag(QuizSource.recent)
                            Text("Favorites").tag(QuizSource.favorites)
                            Text("All").tag(QuizSource.all)
                            ForEach(lists) { list in
                                Text(verbatim: list.name).tag(QuizSource.list(list.id))
                            }
                        }
                        // A segmented picker in a form row hides its own label.
                        LabeledContent("Questions") {
                            Picker("Questions", selection: $draft.quizLength) {
                                Text(verbatim: "5").tag(5)
                                Text(verbatim: "10").tag(10)
                                Text(verbatim: "20").tag(20)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        }
                    }
                case .podcast:
                    Section {
                        Picker("Level", selection: $draft.podcastLevel) {
                            ForEach(LanguageLevel.allCases, id: \.self) { level in
                                Text(verbatim: level.label).tag(level)
                            }
                        }
                        Picker("Length", selection: $draft.podcastLength) {
                            ForEach(PodcastLength.allCases, id: \.self) { length in
                                Text(length.title).tag(length)
                            }
                        }
                        Picker("Style", selection: $draft.podcastStyle) {
                            ForEach(PodcastStyle.allCases, id: \.self) { style in
                                Text(style.title).tag(style)
                            }
                        }
                    }
                }

                Section {
                    WeekdayPicker(selection: $draft.weekdays)
                    DatePicker("Time", selection: $draft.time, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("plan-time")
                } header: {
                    Text("When")
                } footer: {
                    if draft.weekdays.isEmpty {
                        Text("Choose at least one day.")
                    } else {
                        Text(verbatim: PlanText.schedule(draft.schedule))
                    }
                }

                Section {
                    Toggle("Remind Me", isOn: $draft.isEnabled)
                        .accessibilityIdentifier("plan-enabled")
                } footer: {
                    Text("A plan that is off keeps its settings but sends no reminders.")
                }

                if draft.planID != nil {
                    Section {
                        Button("Delete Plan", role: .destructive) { isConfirmingDelete = true }
                            .accessibilityIdentifier("plan-delete")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(verbatim: errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("plan-error")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(draft.planID == nil ? "New Plan" : "Edit Plan")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(draft.language == nil || draft.weekdays.isEmpty)
                    .accessibilityIdentifier("plan-save")
                }
            }
            .confirmationDialog("Delete this plan?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { await delete() }
                }
            } message: {
                Text("Its reminders stop on all your devices.")
            }
            .onAppear(perform: loadLists)
            .onChange(of: draft.language) { loadLists() }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    /// The lists in the plan's language; a list from another language no longer applies.
    private func loadLists() {
        guard let language = draft.language else { return }
        let code = language.rawValue
        lists = (try? app.repository.context.fetch(FetchDescriptor<WordList>(
            predicate: #Predicate { $0.languageCode == code },
            sortBy: [SortDescriptor(\.name)]
        ))) ?? []
        if case .list(let id) = draft.quizSource, !lists.contains(where: { $0.id == id }) {
            draft.quizSource = .due
        }
    }

    private func save() async {
        guard let language = draft.language else { return }
        do {
            // iOS keeps at most 64 pending notifications, so plans can't ask for more.
            let others = try app.activePlans().filter { $0.isEnabled && $0.id != draft.planID }
            let perWeek = others.reduce(draft.isEnabled ? draft.weekdays.count : 0) { $0 + $1.schedule.weekdays.count }
            guard perWeek <= PlanReminders.limit else {
                errorMessage = String(localized: "Plans can remind you at most \(PlanReminders.limit) times a week. Choose fewer days, or turn another plan off.")
                return
            }
            if let id = draft.planID, let plan = try app.plans.plan(id: id) {
                draft.apply(to: plan)
                try app.plans.save()
            } else {
                let plan = StudyPlan(activity: draft.activity, language: language, schedule: draft.schedule)
                draft.apply(to: plan)
                try app.plans.insert(plan)
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        dismiss()
        if draft.isEnabled {
            await app.requestReminderPermission()
        }
        await app.rescheduleReminders()
    }

    private func delete() async {
        if let id = draft.planID, let plan = try? app.plans.plan(id: id) {
            do {
                try app.plans.delete(plan)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        dismiss()
        await app.rescheduleReminders()
    }
}

/// The days a plan runs: a toggle for each day, in the locale's week order. At accessibility text
/// sizes the days are listed one per row, with their full names.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let calendar = Calendar.current

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                ForEach(PlanText.weekdays(calendar: calendar), id: \.self) { weekday in
                    Toggle(calendar.standaloneWeekdaySymbols[weekday - 1], isOn: isOn(weekday))
                        .accessibilityIdentifier("plan-day-\(weekday)")
                }
            }
        } else {
            row
        }
    }

    private func isOn(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { selection.contains(weekday) },
            set: { isOn in
                if isOn {
                    selection.insert(weekday)
                } else {
                    selection.remove(weekday)
                }
            }
        )
    }

    private var row: some View {
        HStack(spacing: 6) {
            ForEach(PlanText.weekdays(calendar: calendar), id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    if isOn {
                        selection.remove(weekday)
                    } else {
                        selection.insert(weekday)
                    }
                } label: {
                    Text(verbatim: calendar.shortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.15)), in: .capsule)
                }
                // Each day is its own button; in a form row, default buttons share one tap.
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: calendar.standaloneWeekdaySymbols[weekday - 1]))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("plan-day-\(weekday)")
            }
        }
    }
}
