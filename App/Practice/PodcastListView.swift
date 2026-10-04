import SwiftData
import SwiftUI
import VocabularyCore
import VocabularyData

/// Every podcast episode in the learner's languages, newest first, with delete (SPEC C9).
struct PodcastListView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \PodcastEpisode.createdAt, order: .reverse) private var episodes: [PodcastEpisode]
    @State private var errorMessage: String?

    var body: some View {
        let visible = episodes.visible(for: app.settings.profile)
        List {
            ForEach(visible) { episode in
                NavigationLink(value: PracticeRoute.episode(episode)) {
                    PodcastEpisodeRow(episode: episode)
                }
                .accessibilityIdentifier("podcast-list-episode")
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(episode) }
                }
            }
            .onDelete { offsets in
                offsets.map { visible[$0] }.forEach(delete)
            }
        }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView("No Podcasts", systemImage: "waveform", description: Text("Podcasts you create appear here."))
            }
        }
        .navigationTitle("Podcasts")
        .alert("Couldn't Delete the Podcast", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func delete(_ episode: PodcastEpisode) {
        do {
            try app.podcasts.delete(episode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// An episode's title, with its language, level, style and date.
struct PodcastEpisodeRow: View {
    let episode: PodcastEpisode

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: episode.title)
            Text(verbatim: details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        [
            episode.language?.localizedName() ?? episode.languageCode,
            episode.level.label,
            String(localized: episode.style.title),
            episode.createdAt.formatted(date: .abbreviated, time: .omitted),
        ].joined(separator: " · ")
    }
}

extension [PodcastEpisode] {
    /// Episodes in the languages the learner is learning: removing a language hides its words and
    /// podcasts, and adding it back shows them again (SPEC C1).
    func visible(for profile: LearnerProfile?) -> [PodcastEpisode] {
        let learning = Set(profile?.learning.map(\.rawValue) ?? [])
        return filter { learning.contains($0.languageCode) }
    }
}

extension PodcastStyle {
    var title: LocalizedStringResource {
        switch self {
        case .dialogue: "Dialogue"
        case .story: "Story"
        }
    }
}

extension PodcastLength {
    var title: LocalizedStringResource {
        switch self {
        case .short: "About 2 minutes"
        case .long: "About 5 minutes"
        }
    }
}
