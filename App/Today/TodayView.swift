import SwiftUI
import VocabularyCore
import VocabularyData
import VocabularyUI

/// Today: what is due in each learning language, and the way into a review session (SPEC C7).
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var summaries: [Summary] = []
    @State private var wordCount = 0
    @State private var session: ReviewSessionModel?
    @State private var errorMessage: String?

    struct Summary: Identifiable, Equatable {
        let language: LanguageCode
        let due: Int
        let new: Int

        var id: LanguageCode { language }
        var isDone: Bool { due + new == 0 }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Today")
        }
        .onAppear(perform: refresh)
        .onChange(of: app.navigation.startingPlan, initial: true) { startPlan() }
        .onChange(of: scenePhase) { _, phase in
            // A new day may have started while the app was in the background.
            if phase == .active { refresh() }
        }
        .sheet(isPresented: isReviewing, onDismiss: refresh) {
            if let session {
                FlashcardSessionView(model: session) { self.session = nil }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if wordCount == 0 {
            ContentUnavailableView(
                "Nothing to review yet",
                systemImage: "sun.max",
                description: Text("Words you capture will be scheduled for review here.")
            )
        } else {
            List {
                Section {
                    ForEach(summaries) { summary in
                        row(for: summary)
                    }
                } header: {
                    Text("Reviews")
                } footer: {
                    Text("Up to \(app.settings.reviewLimits.newPerDay) new words and \(app.settings.reviewLimits.reviewsPerDay) reviews a day.")
                }
                if let errorMessage {
                    Section {
                        Text(verbatim: errorMessage).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func row(for summary: Summary) -> some View {
        AdaptiveStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: summary.language.localizedName())
                    .font(.headline)
                Group {
                    if summary.isDone {
                        Text("All done for today")
                    } else {
                        Text("\(summary.due) due · \(summary.new) new")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("today-counts-\(summary.language.rawValue)")
            }
            Spacer()
            Button("Review") {
                start(summary.language)
            }
            .buttonStyle(.borderedProminent)
            .disabled(summary.isDone)
            .accessibilityIdentifier("today-review-\(summary.language.rawValue)")
        }
        .padding(.vertical, 4)
    }

    private var isReviewing: Binding<Bool> {
        Binding(get: { session != nil }, set: { if !$0 { session = nil } })
    }

    private func refresh() {
        guard let languages = app.settings.profile?.learning else {
            summaries = []
            wordCount = 0
            return
        }
        do {
            summaries = try languages.map { language in
                let queue = try app.reviews.queue(language: language, limits: app.settings.reviewLimits)
                return Summary(language: language, due: queue.reviewCount, new: queue.newCount)
            }
            wordCount = try languages.reduce(0) { $0 + (try app.repository.count(language: $1)) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Starts a review plan's flashcards, unless that language has nothing left for today
    /// (SPEC C10).
    private func startPlan() {
        guard let plan = app.navigation.takePlan(for: [.review]), let language = plan.language else { return }
        refresh()
        if summaries.first(where: { $0.language == language })?.isDone == false {
            start(language)
        }
    }

    private func start(_ language: LanguageCode) {
        do {
            session = try ReviewSessionModel(language: language, limits: app.settings.reviewLimits, repository: app.reviews)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    TodayView().environment(AppModel.preview())
}
