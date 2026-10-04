import SwiftData
import SwiftUI
import VocabularyData
import VocabularyUI

/// Where the Practice tab navigates.
enum PracticeRoute: Hashable {
    case newPodcast
    case episode(PodcastEpisode)
    case episodes
}

/// Practice: quizzes and podcasts on saved words (SPEC C8, C9).
struct PracticeView: View {
    @State private var quiz: QuizSessionModel?
    @State private var refreshToken = UUID()
    @State private var path: [PracticeRoute] = []
    @Environment(AppModel.self) private var app
    #if DEBUG
    @State private var didOpenLaunchScreen = false
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                QuizSetupView(refreshToken: refreshToken) { quiz = $0 }
                PodcastsSection()
            }
            .formStyle(.grouped)
            .navigationTitle("Practice")
            #if DEBUG
            .onAppear(perform: openLaunchScreen)
            #endif
            .navigationDestination(for: PracticeRoute.self) { route in
                switch route {
                case .newPodcast:
                    PodcastSetupView { episode in
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
            path = [.newPodcast]
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
            NavigationLink(value: PracticeRoute.newPodcast) {
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
