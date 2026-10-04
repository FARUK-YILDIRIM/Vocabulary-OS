import SwiftData
import SwiftUI
import VocabularyData
import VocabularyUI

/// Where the Practice tab navigates.
enum PracticeRoute: Hashable {
    /// A study plan's podcast starts writing at once.
    case newPodcast(PodcastPlan?)
    case episode(PodcastEpisode)
    case episodes
}

/// Practice: quizzes, podcasts and the study plans that start them (SPEC C8, C9, C10).
struct PracticeView: View {
    @State private var quiz: QuizSessionModel?
    @State private var refreshToken = UUID()
    @State private var path: [PracticeRoute] = []
    @State private var planDraft: PlanDraft?
    @State private var planError: String?
    @Environment(AppModel.self) private var app
    #if DEBUG
    @State private var didOpenLaunchScreen = false
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                QuizSetupView(refreshToken: refreshToken) { quiz = $0 }
                PodcastsSection()
                PlansSection(draft: $planDraft)
            }
            .formStyle(.grouped)
            .navigationTitle("Practice")
            .sheet(item: $planDraft) { draft in
                PlanEditorView(draft: draft)
            }
            #if DEBUG
            .onAppear(perform: openLaunchScreen)
            #endif
            .navigationDestination(for: PracticeRoute.self) { route in
                switch route {
                case .newPodcast(let plan):
                    PodcastSetupView(plan: plan) { episode in
                        // The new episode takes the setup screen's place.
                        path.removeLast()
                        path.append(.episode(episode))
                    }
                case .episode(let episode):
                    PodcastPlayerView(episode: episode)
                case .episodes:
                    PodcastListView()
                }
            }
        }
        .sheet(isPresented: isQuizzing, onDismiss: { refreshToken = UUID() }) {
            if let quiz {
                QuizSessionView(model: quiz) {
                    quiz.cancel()
                    self.quiz = nil
                }
            }
        }
        .onChange(of: app.navigation.startingPlan, initial: true) { startPlan() }
        .alert("The Plan Couldn't Start", isPresented: isShowingPlanError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: planError ?? "")
        }
    }

    private var isShowingPlanError: Binding<Bool> {
        Binding(get: { planError != nil }, set: { if !$0 { planError = nil } })
    }

    /// Starts a plan's quiz or podcast, as its reminder or link asks (SPEC C10).
    private func startPlan() {
        guard let plan = app.navigation.takePlan(for: [.quiz, .podcast]), let language = plan.language else { return }
        switch plan.activity {
        case .quiz:
            do {
                let session = try app.makeQuiz(language: language, source: plan.quizSource, length: plan.quizLength)
                quiz?.cancel()
                quiz = session
            } catch {
                planError = error.localizedDescription
            }
        case .podcast:
            path = [.newPodcast(PodcastPlan(language: language, level: plan.podcastLevel, length: plan.podcastLength, style: plan.podcastStyle))]
        case .review:
            break
        }
    }

    private var isQuizzing: Binding<Bool> {
        Binding(get: { quiz != nil }, set: { if !$0 { quiz = nil } })
    }

    #if DEBUG
    /// `-vos-podcast new` or `newest` opens a podcast screen at launch, for screenshots.
    private func openLaunchScreen() {
        guard !didOpenLaunchScreen, path.isEmpty else { return }
        didOpenLaunchScreen = true
        switch LaunchOptions().podcastScreen {
        case "new":
            path = [.newPodcast(nil)]
        case "newest":
            var newest = FetchDescriptor<PodcastEpisode>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            newest.fetchLimit = 1
            if let episode = try? app.repository.context.fetch(newest).first {
                path = [.episode(episode)]
            }
        default:
            break
        }
    }
    #endif
}

/// The Practice form's podcasts: a new episode and the latest ones.
private struct PodcastsSection: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \PodcastEpisode.createdAt, order: .reverse) private var episodes: [PodcastEpisode]

    private static let recentCount = 3

    var body: some View {
        let visible = episodes.visible(for: app.settings.profile)
        Section {
            NavigationLink(value: PracticeRoute.newPodcast(nil)) {
                Label("New Podcast", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("practice-new-podcast")
            ForEach(visible.prefix(Self.recentCount)) { episode in
                NavigationLink(value: PracticeRoute.episode(episode)) {
                    PodcastEpisodeRow(episode: episode)
                }
            }
            // The full list is also where episodes are deleted.
            if !visible.isEmpty {
                NavigationLink(value: PracticeRoute.episodes) {
                    LabeledContent("All Episodes", value: visible.count, format: .number)
                }
                .accessibilityIdentifier("practice-all-podcasts")
            }
        } header: {
            Text("Podcasts")
        } footer: {
            Text("A short dialogue or story that uses your words, read aloud by your device.")
        }
    }
}

#Preview {
    PracticeView().environment(AppModel.preview())
}
