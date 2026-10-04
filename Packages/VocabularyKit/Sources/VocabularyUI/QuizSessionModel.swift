import Foundation
import Observation
import VocabularyAI
import VocabularyCore
import VocabularyData

/// A quiz session (SPEC C8): one question per word, written while the learner answers the previous
/// one, with every answer recorded as a review (right → Good, wrong → Again).
@Observable
public final class QuizSessionModel {
    public enum Phase: Equatable {
        /// Writing the next question.
        case preparing
        case asking
        case answered(correct: Bool)
        case finished
    }

    public let language: LanguageCode
    /// Questions planned; words without a usable question are skipped.
    public let total: Int
    public private(set) var phase = Phase.preparing
    public private(set) var current: QuizQuestion?
    public private(set) var selectedOption: Int?
    public private(set) var answeredCount = 0
    public private(set) var correctCount = 0
    /// Words answered wrong, to repeat.
    public private(set) var missed: [QuizWord] = []
    public private(set) var errorMessage: String?

    private let plan: [QuizPlanItem]
    private let library: [QuizWord]
    private let source: QuizSource
    private let service: QuizService
    private let reviews: ReviewRepository
    private let quizzes: QuizRepository
    private let calendar: Calendar
    private let now: () -> Date
    private let startedAt: Date
    private var position = 0
    private var questions: [Int: Task<QuizQuestion?, Never>] = [:]
    private var hasStarted = false

    /// - Parameters:
    ///   - words: the words to ask about, in order; one question each.
    ///   - library: saved words that supply wrong answers.
    ///   - kinds: question kinds to mix.
    public init(
        language: LanguageCode,
        words: [VocabularyEntry],
        library: [VocabularyEntry],
        kinds: [QuizKind],
        source: QuizSource,
        service: QuizService,
        reviews: ReviewRepository,
        quizzes: QuizRepository,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date.now }
    ) {
        self.language = language
        let kinds = kinds.isEmpty ? [.meaning] : kinds.shuffled()
        plan = words.enumerated().map { index, entry in
            QuizPlanItem(kind: kinds[index % kinds.count], word: entry.quizWord)
        }
        total = plan.count
        self.library = library.map(\.quizWord)
        self.source = source
        self.service = service
        self.reviews = reviews
        self.quizzes = quizzes
        self.calendar = calendar
        self.now = now
        startedAt = now()
    }

    /// Prepares the first question. Cloud models write the whole quiz in one call first. Later calls
    /// do nothing, since a view may start the session more than once.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        if service.strategy == .singleCall {
            let written = (try? await service.questions(for: plan, library: library)) ?? []
            for (index, item) in plan.enumerated() {
                let question = written.first { $0.wordID == item.word.id }
                questions[index] = Task { [library] in
                    question ?? Self.localQuestion(for: item, library: library)
                }
            }
        }
        await showCurrent()
    }

    /// The word a question asks about.
    public func word(for question: QuizQuestion) -> QuizWord? {
        plan.first { $0.word.id == question.wordID }?.word
    }

    public func answer(_ option: Int) {
        guard phase == .asking, let question = current else { return }
        selectedOption = option
        let correct = option == question.answerIndex
        answeredCount += 1
        if correct {
            correctCount += 1
        } else if let word = word(for: question) {
            missed.append(word)
        }
        // Fetched again: the word may have been deleted since the quiz started, here or on another
        // device, and a deleted model must not be touched.
        if let entry = try? reviews.entry(id: question.wordID) {
            do {
                try reviews.record(correct ? .good : .again, for: entry, mode: .quiz, now: now(), calendar: calendar)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        phase = .answered(correct: correct)
    }

    public func next() async {
        guard case .answered = phase else { return }
        position += 1
        await showCurrent()
    }

    /// Stops writing questions, for a quiz closed early.
    public func cancel() {
        questions.values.forEach { $0.cancel() }
    }

    // MARK: Questions

    private func showCurrent() async {
        phase = .preparing
        current = nil
        selectedOption = nil
        while let pending = task(for: position) {
            let question = await pending.value
            // Write the next question while the learner answers this one.
            _ = task(for: position + 1)
            if let question {
                current = question
                phase = .asking
                return
            }
            position += 1
        }
        finish()
    }

    private func task(for index: Int) -> Task<QuizQuestion?, Never>? {
        guard plan.indices.contains(index) else { return nil }
        if let existing = questions[index] { return existing }
        let item = plan[index]
        let task = Task { [service, library] in
            await Self.question(for: item, service: service, library: library)
        }
        questions[index] = task
        return task
    }

    private static func question(for item: QuizPlanItem, service: QuizService, library: [QuizWord]) async -> QuizQuestion? {
        if let question = try? await service.question(item.kind, for: item.word, library: library) {
            return question
        }
        return localQuestion(for: item, library: library)
    }

    /// Built from saved words when the model couldn't write the question; a meaning question when
    /// even that isn't possible (a cloze question without a saved sentence).
    private static func localQuestion(for item: QuizPlanItem, library: [QuizWord]) -> QuizQuestion? {
        var generator = SystemRandomNumberGenerator()
        return QuizBuilder.fallback(item.kind, for: item.word, library: library, using: &generator)
            ?? QuizBuilder.fallback(.meaning, for: item.word, library: library, using: &generator)
    }

    private func finish() {
        phase = .finished
        current = nil
        guard answeredCount > 0 else { return }
        let record = QuizRecord(
            language: language, source: source, startedAt: startedAt, finishedAt: now(),
            questionCount: answeredCount, correctCount: correctCount
        )
        do {
            try quizzes.save(record)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
