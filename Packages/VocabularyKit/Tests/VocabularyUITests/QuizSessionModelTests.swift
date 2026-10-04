import Foundation
import FoundationModels
import Testing
import VocabularyAI
import VocabularyCore
import VocabularyData
@testable import VocabularyUI

@Suite struct QuizSessionModelTests {
    private let words: WordRepository
    private let reviews: ReviewRepository
    private let quizzes: QuizRepository
    private let calendar: Calendar
    private let now: Date

    init() throws {
        words = WordRepository(container: try VocabularyStore.makeContainer(inMemory: true, cloudSync: false))
        reviews = ReviewRepository(words: words)
        quizzes = QuizRepository(words: words)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 10))!
        let samples = [
            ("cookies", "çerez", "This website uses cookies for tracking."),
            ("pitch", "sunum", "She gave a great pitch to the investors."),
            ("umbrella", "şemsiye", "Take an umbrella, it is raining."),
            ("apple", "elma", "He ate an apple after lunch."),
            ("train", "tren", "The train was late again."),
        ]
        for (term, translation, sentence) in samples {
            _ = try words.save(
                WordInsight(term: term, lemma: term, partOfSpeech: .noun, language: .english, nativeLanguage: .turkish,
                            context: sentence, translation: translation, meaning: "Anlam.", source: InsightSource(providerID: "test")),
                captureSource: .text
            )
        }
    }

    private func makeSession(kinds: [QuizKind] = [.meaning, .reverse, .cloze]) throws -> QuizSessionModel {
        let entries = try words.entries(language: .english, sort: .oldest)
        // No model here: cloze questions fall back to the saved sentences.
        let service = QuizService(client: OfflineClient(), strategy: .stepwise, source: InsightSource(providerID: "test"))
        return QuizSessionModel(
            language: .english, words: entries, library: entries, kinds: kinds, source: .all,
            service: service, reviews: reviews, quizzes: quizzes, calendar: calendar
        ) { [now] in now }
    }

    @Test func startsWithAValidQuestion() async throws {
        let session = try makeSession()
        await session.start()

        #expect(session.phase == .asking)
        #expect(session.total == 5)
        let question = try #require(session.current)
        let word = try #require(session.word(for: question))
        try QuizValidator.validate(question, for: word)
    }

    @Test func aRightAnswerCountsAsGoodAndAWrongOneAsAgain() async throws {
        let session = try makeSession()
        await session.start()
        let first = try #require(session.current)
        session.answer(first.answerIndex)
        #expect(session.phase == .answered(correct: true))
        #expect(session.correctCount == 1)
        let firstEntry = try #require(try reviews.entry(id: first.wordID))
        #expect(firstEntry.repetitions == 1)

        await session.next()
        let second = try #require(session.current)
        session.answer((second.answerIndex + 1) % 4)
        #expect(session.phase == .answered(correct: false))
        let secondEntry = try #require(try reviews.entry(id: second.wordID))
        #expect(secondEntry.lapses == 1)
        #expect(session.missed.map(\.id) == [second.wordID])
        #expect(secondEntry.reviewLogs?.first?.mode == .quiz)
    }

    @Test func aWordAlreadyReviewedTodayKeepsItsSchedule() async throws {
        let session = try makeSession()
        await session.start()
        let question = try #require(session.current)
        let entry = try #require(try reviews.entry(id: question.wordID))
        try reviews.record(.good, for: entry, mode: .flashcard, now: now, calendar: calendar)
        let scheduled = entry.cardState

        session.answer((question.answerIndex + 1) % 4)
        #expect(entry.cardState == scheduled)
        #expect(entry.reviewLogs?.count == 2)
        #expect(entry.reviewLogs?.contains { $0.mode == .quiz && !$0.changedSchedule } == true)
    }

    @Test func finishingSavesTheResult() async throws {
        let session = try makeSession()
        await session.start()
        var answered = 0
        while let question = session.current, session.phase == .asking {
            session.answer(answered.isMultiple(of: 2) ? question.answerIndex : (question.answerIndex + 1) % 4)
            answered += 1
            await session.next()
        }

        #expect(session.phase == .finished)
        #expect(session.answeredCount == 5)
        #expect(session.correctCount == 3)
        let record = try #require(try quizzes.records(language: .english).first)
        #expect(record.questionCount == 5)
        #expect(record.correctCount == 3)
        #expect(record.source == .all)
    }
}

@Suite struct QuizRepositoryTests {
    private let words: WordRepository
    private let quizzes: QuizRepository
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        words = WordRepository(container: try VocabularyStore.makeContainer(inMemory: true, cloudSync: false))
        quizzes = QuizRepository(words: words)
    }

    @discardableResult
    private func save(_ term: String, createdDaysAgo: Double, favorite: Bool = false, state: CardState? = nil) throws -> VocabularyEntry {
        let entry = try words.save(
            WordInsight(term: term, lemma: term, language: .german, nativeLanguage: .turkish, translation: term,
                        meaning: "Anlam.", source: InsightSource(providerID: "test")),
            captureSource: .text
        )
        entry.createdAt = now.addingTimeInterval(-createdDaysAgo * 86_400)
        entry.isFavorite = favorite
        if let state { entry.cardState = state }
        return entry
    }

    @Test func picksWordsBySource() throws {
        try save("neu", createdDaysAgo: 1)
        try save("alt", createdDaysAgo: 30, favorite: true,
                 state: CardState(intervalDays: 20, repetitions: 3, dueAt: now.addingTimeInterval(86_400 * 5), lastReviewedAt: now))
        try save("fällig", createdDaysAgo: 10,
                 state: CardState(intervalDays: 6, repetitions: 2, dueAt: now.addingTimeInterval(-86_400), lastReviewedAt: now.addingTimeInterval(-86_400 * 7)))

        #expect(try quizzes.words(language: .german, source: .due, limit: 10, now: now).map(\.term).sorted() == ["fällig", "neu"])
        #expect(try quizzes.words(language: .german, source: .recent, limit: 2, now: now).map(\.term) == ["neu", "fällig"])
        #expect(try quizzes.words(language: .german, source: .favorites, limit: 10, now: now).map(\.term) == ["alt"])
        #expect(try quizzes.words(language: .german, source: .all, limit: 10, now: now).count == 3)
        #expect(try quizzes.words(language: .german, source: .all, limit: 2, now: now).count == 2)
    }

    @Test func aListSourceUsesTheListsWords() throws {
        let first = try save("eins", createdDaysAgo: 1)
        try save("zwei", createdDaysAgo: 2)
        let list = try words.createList(named: "Reise", language: .german)
        words.add(first, to: list)

        #expect(try quizzes.words(language: .german, source: .list(list.id), limit: 10, now: now).map(\.term) == ["eins"])
    }
}

/// A provider that is never reachable, so every question comes from saved words.
private struct OfflineClient: GenerationClient {
    func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent {
        throw .network("offline")
    }
}
