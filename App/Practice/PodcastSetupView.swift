import SwiftUI
import VocabularyAI
import VocabularyCore
import VocabularyData
import VocabularyUI

/// A new podcast: a language, 3 to 12 saved words, a level, a length and a style (SPEC C9). The AI
/// writes the script; the new episode then opens in the player.
struct PodcastSetupView: View {
    let onCreate: (PodcastEpisode) -> Void
    @Environment(AppModel.self) private var app
    @State private var language: LanguageCode?
    /// The language's words, due ones first, then the most recent.
    @State private var entries: [VocabularyEntry] = []
    @State private var chosen: Set<UUID> = []
    @AppStorage("podcast.level") private var level = LanguageLevel.a2
    @AppStorage("podcast.length") private var length = PodcastLength.short
    @AppStorage("podcast.style") private var style = PodcastStyle.dialogue
    @State private var creation: PodcastCreationModel?
    @State private var writing: Task<Void, Never>?
    @State private var loadError: String?

    /// How many words a new podcast starts with.
    private static let suggestedWordCount = 5

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $language) {
                    ForEach(app.settings.profile?.learning ?? [], id: \.self) { code in
                        Text(verbatim: code.localizedName()).tag(Optional(code))
                    }
                }
                .accessibilityIdentifier("podcast-language")
                NavigationLink {
                    PodcastWordPicker(entries: entries, chosen: $chosen)
                } label: {
                    LabeledContent("Words") {
                        Text("^[\(chosen.count) word](inflect: true)")
                            .accessibilityIdentifier("podcast-word-count")
                    }
                }
                .disabled(entries.isEmpty)
                .accessibilityIdentifier("podcast-words")
            } footer: {
                if let language, entries.count < PodcastCreationModel.wordCount.lowerBound {
                    Text("Save at least \(PodcastCreationModel.wordCount.lowerBound) \(language.localizedName()) words to make a podcast.")
                } else {
                    Text(verbatim: chosenWords.map(\.term).joined(separator: ", "))
                }
            }
            // Leaving for the word list would cancel the writing.
            .disabled(isWriting)

            Section {
                Picker("Level", selection: $level) {
                    ForEach(LanguageLevel.allCases, id: \.self) { level in
                        Text(verbatim: level.label).tag(level)
                    }
                }
                .accessibilityIdentifier("podcast-level")
                Picker("Length", selection: $length) {
                    ForEach(PodcastLength.allCases, id: \.self) { length in
                        Text(length.title).tag(length)
                    }
                }
                .accessibilityIdentifier("podcast-length")
                Picker("Style", selection: $style) {
                    ForEach(PodcastStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .accessibilityIdentifier("podcast-style")
            } footer: {
                Text(style == .dialogue ? "Two hosts talk about an everyday topic." : "A narrator tells a short story.")
            }
            .disabled(isWriting)

            Section {
                if isWriting {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Writing the script…")
                        Spacer()
                        Button("Cancel", action: cancel)
                    }
                    .accessibilityIdentifier("podcast-writing")
                } else {
                    Button(action: create) {
                        Label("Create Podcast", systemImage: "waveform")
                    }
                    .disabled(!canCreate)
                    .accessibilityIdentifier("podcast-create")
                }
            } footer: {
                if case .failed(let message) = creation?.phase {
                    Text(verbatim: message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("podcast-error")
                } else if let loadError {
                    Text(verbatim: loadError).foregroundStyle(.red)
                } else if app.settings.aiSelection == .onDevice {
                    Text("Apple Intelligence writes the script on this device, which can take a minute.")
                } else {
                    Text("\(app.providerDisplayName) writes the script.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New Podcast")
        .onAppear {
            if creation == nil {
                creation = PodcastCreationModel(podcasts: app.podcasts) { [app] in PodcastService(app.makeInsightService()) }
            }
            if language == nil {
                language = app.settings.profile?.learning.first
            }
        }
        .onChange(of: language) { loadWords() }
        .onDisappear { writing?.cancel() }
    }

    private var isWriting: Bool { creation?.phase == .writing }

    private var chosenWords: [VocabularyEntry] {
        entries.filter { chosen.contains($0.id) }
    }

    private var canCreate: Bool {
        language != nil && PodcastCreationModel.wordCount.contains(chosen.count) && !isWriting
    }

    private func loadWords() {
        guard let language else { return }
        do {
            let due = try app.quizzes.words(language: language, source: .due, limit: .max)
            let recent = try app.quizzes.words(language: language, source: .recent, limit: .max)
            var seen: Set<UUID> = []
            entries = (due + recent).filter { seen.insert($0.id).inserted }
            chosen = Set(entries.prefix(Self.suggestedWordCount).map(\.id))
            loadError = nil
        } catch {
            entries = []
            chosen = []
            loadError = error.localizedDescription
        }
    }

    private func create() {
        guard let language, let creation, let native = app.settings.profile?.native else { return }
        let words = chosenWords
        writing = Task {
            if let episode = await creation.create(
                words: words, language: language, nativeLanguage: native, level: level, length: length, style: style
            ) {
                onCreate(episode)
            }
        }
    }

    private func cancel() {
        writing?.cancel()
        writing = nil
    }
}

/// Choosing a podcast's words from the language's saved words, at most 12.
private struct PodcastWordPicker: View {
    let entries: [VocabularyEntry]
    @Binding var chosen: Set<UUID>
    @State private var search = ""

    var body: some View {
        List(filtered) { entry in
            let isChosen = chosen.contains(entry.id)
            Button {
                if isChosen {
                    chosen.remove(entry.id)
                } else {
                    chosen.insert(entry.id)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: entry.term)
                        Text(verbatim: entry.translation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isChosen {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!isChosen && chosen.count >= PodcastCreationModel.wordCount.upperBound)
            .accessibilityAddTraits(isChosen ? .isSelected : [])
            .accessibilityIdentifier("podcast-word-\(entry.term)")
        }
        .searchable(text: $search)
        .navigationTitle("Words")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text("\(chosen.count) of \(PodcastCreationModel.wordCount.upperBound)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var filtered: [VocabularyEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.term.localizedStandardContains(query) || $0.translation.localizedStandardContains(query)
        }
    }
}

#Preview {
    NavigationStack {
        PodcastSetupView { _ in }
    }
    .environment(AppModel.preview())
}
