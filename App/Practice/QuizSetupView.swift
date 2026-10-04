import SwiftData
import SwiftUI
import VocabularyAI
import VocabularyCore
import VocabularyData
import VocabularyUI

/// Quiz setup: a language, which words, and how many questions (SPEC C8). A section of the
/// Practice form; the form presents the quiz, since presentations attached to a section don't show.
struct QuizSetupView: View {
    /// Changes when a quiz ends, so the counts are read again.
    let refreshToken: UUID
    let onStart: (QuizSessionModel) -> Void
    @Environment(AppModel.self) private var app
    @State private var language: LanguageCode?
    @State private var source = QuizSource.due
    @State private var length = 10
    @State private var lists: [WordList] = []
    @State private var matching = 0
    @State private var languageWordCount = 0
    @State private var errorMessage: String?

    /// Listening questions join once the app can speak words (task T26).
    private static let kinds: [QuizKind] = [.meaning, .reverse, .cloze]

    var body: some View {
        Section {
            Picker("Language", selection: $language) {
                ForEach(app.settings.profile?.learning ?? [], id: \.self) { code in
                    Text(verbatim: code.localizedName()).tag(Optional(code))
                }
            }
            .accessibilityIdentifier("quiz-language")
            Picker("Words", selection: $source) {
                Text("Due").tag(QuizSource.due)
                Text("Recent").tag(QuizSource.recent)
                Text("Favorites").tag(QuizSource.favorites)
                Text("All").tag(QuizSource.all)
                ForEach(lists) { list in
                    Text(verbatim: list.name).tag(QuizSource.list(list.id))
                }
            }
            .accessibilityIdentifier("quiz-source")
            // A segmented picker in a form row hides its own label.
            LabeledContent("Questions") {
                Picker("Questions", selection: $length) {
                    Text(verbatim: "5").tag(5)
                    Text(verbatim: "10").tag(10)
                    Text(verbatim: "20").tag(20)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
                .accessibilityIdentifier("quiz-length")
            }
            Button("Start Quiz", action: start)
                .disabled(!canStart)
                .accessibilityIdentifier("quiz-start")
        } header: {
            Text("Quiz")
        } footer: {
            Group {
                if languageWordCount < QuizRepository.minimumWords, let language {
                    Text("Save at least \(QuizRepository.minimumWords) \(language.localizedName()) words to make a quiz: the wrong answers come from your other words.")
                } else if matching == 0 {
                    Text("No words match.")
                } else {
                    Text("^[\(min(matching, length)) question](inflect: true) from your words. Every answer counts as a review.")
                }
            }
            .accessibilityIdentifier("quiz-footer")
        }
        .onAppear {
            if language == nil { language = app.settings.profile?.learning.first }
            refresh()
        }
        .onChange(of: language) { refresh() }
        .onChange(of: source) { refresh() }
        .onChange(of: length) { refresh() }
        .onChange(of: refreshToken) { refresh() }
        if let errorMessage {
            Section {
                Text(verbatim: errorMessage).foregroundStyle(.red)
            }
        }
    }

    private var canStart: Bool {
        language != nil && languageWordCount >= QuizRepository.minimumWords && matching > 0
    }

    private func refresh() {
        guard let language else { return }
        do {
            let code = language.rawValue
            lists = try app.repository.context.fetch(FetchDescriptor<WordList>(
                predicate: #Predicate { $0.languageCode == code },
                sortBy: [SortDescriptor(\.name)]
            ))
            languageWordCount = try app.repository.count(language: language)
            matching = try app.quizzes.words(language: language, source: source, limit: .max).count
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func start() {
        guard let language else { return }
        do {
            onStart(QuizSessionModel(
                language: language,
                words: try app.quizzes.words(language: language, source: source, limit: length),
                library: try app.quizzes.library(),
                kinds: Self.kinds,
                source: source,
                service: QuizService(app.makeInsightService()),
                reviews: app.reviews,
                quizzes: app.quizzes
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
