import Foundation
import SwiftData
import Testing
import VocabularyCore
@testable import VocabularyData

@MainActor
@Suite struct ReviewRepositoryTests {
    private let words: WordRepository
    private let reviews: ReviewRepository
    private let calendar: Calendar
    private let now: Date

    init() throws {
        words = WordRepository(container: try VocabularyStore.makeContainer(inMemory: true, cloudSync: false))
        reviews = ReviewRepository(words: words)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 10))!
    }

    @discardableResult
    private func save(_ term: String, _ language: LanguageCode = .english, state: CardState? = nil) throws -> VocabularyEntry {
        let insight = WordInsight(term: term, lemma: term, language: language, nativeLanguage: .turkish,
                                  translation: "çeviri", meaning: "Anlam.", source: InsightSource(providerID: "test"))
        let entry = try words.save(insight, captureSource: .text)
        if let state {
            entry.cardState = state
        }
        return entry
    }

    private func dueState(daysAgo: Int) -> CardState {
        CardState(intervalDays: 6, repetitions: 2, dueAt: now.addingTimeInterval(Double(-daysAgo) * 86_400),
                  lastReviewedAt: now.addingTimeInterval(-7 * 86_400))
    }

    @Test func reviewingMovesTheDueDateAndWritesALog() throws {
        let entry = try save("cookies")
        let log = try reviews.record(.good, for: entry, mode: .flashcard, now: now, calendar: calendar)

        #expect(entry.repetitions == 1)
        #expect(entry.dueAt == calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!)
        #expect(entry.lastReviewedAt == now)
        #expect(log.rating == .good)
        #expect(log.mode == .flashcard)
        #expect(log.entry === entry)
        #expect(log.languageCode == "en")
        #expect(log.intervalBefore == 0 && log.intervalAfter == 1)
        #expect(log.wasNew && log.changedSchedule)
        #expect(try words.context.fetchCount(FetchDescriptor<ReviewLog>()) == 1)
    }

    @Test func laterAnswersTheSameDayAreLoggedWithoutMovingTheSchedule() throws {
        let entry = try save("cookies")
        try reviews.record(.again, for: entry, mode: .flashcard, now: now, calendar: calendar)
        let due = entry.dueAt
        let second = try reviews.record(.easy, for: entry, mode: .quiz, now: now.addingTimeInterval(600), calendar: calendar)

        #expect(entry.dueAt == due)
        #expect(entry.lapses == 1)
        #expect(!second.changedSchedule)
        #expect(!second.wasNew)
        #expect(try words.context.fetchCount(FetchDescriptor<ReviewLog>()) == 2)
    }

    @Test func todaysCountsMatchTheLibrary() throws {
        try save("cookies")
        try save("pitch", state: dueState(daysAgo: 1))
        try save("ran", state: dueState(daysAgo: 3))
        try save("later", state: CardState(intervalDays: 6, repetitions: 2, dueAt: now.addingTimeInterval(86_400), lastReviewedAt: now))
        try save("Bank", .german)

        let english = try reviews.queue(language: .english, limits: ReviewLimits(), now: now, calendar: calendar)
        #expect(english.reviewCount == 2)
        #expect(english.newCount == 1)
        let german = try reviews.queue(language: .german, limits: ReviewLimits(), now: now, calendar: calendar)
        #expect(german.reviewCount == 0)
        #expect(german.newCount == 1)
    }

    @Test func wordsReviewedTodayCountAgainstTheDailyLimits() throws {
        let first = try save("one")
        try save("two")
        try save("three")
        let due = try save("due", state: dueState(daysAgo: 1))
        try reviews.record(.good, for: first, mode: .flashcard, now: now, calendar: calendar)
        try reviews.record(.again, for: first, mode: .flashcard, now: now, calendar: calendar)
        try reviews.record(.good, for: due, mode: .quiz, now: now, calendar: calendar)

        let progress = try reviews.progress(language: .english, now: now.addingTimeInterval(3_600), calendar: calendar)
        #expect(progress == DailyQueue.Progress(reviews: 1, newWords: 1))

        let queue = try reviews.queue(language: .english, limits: ReviewLimits(newPerDay: 2, reviewsPerDay: 1), now: now.addingTimeInterval(3_600), calendar: calendar)
        #expect(queue.newCount == 1)
        #expect(queue.reviewCount == 0)

        // A new day starts with fresh limits.
        let tomorrow = try reviews.progress(language: .english, now: now.addingTimeInterval(86_400), calendar: calendar)
        #expect(tomorrow == DailyQueue.Progress())
    }

    @Test func deletingAWordDeletesItsLog() throws {
        let entry = try save("cookies")
        try reviews.record(.good, for: entry, mode: .flashcard, now: now, calendar: calendar)
        try words.delete(entry)
        #expect(try words.context.fetchCount(FetchDescriptor<ReviewLog>()) == 0)
    }

    @Test func findsAWordByItsID() throws {
        let entry = try save("cookies")
        #expect(try reviews.entry(id: entry.id) === entry)
        #expect(try reviews.entry(id: UUID()) == nil)
    }
}
