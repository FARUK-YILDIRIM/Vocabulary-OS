import Foundation
import Testing
import VocabularyCore
import VocabularyData
@testable import VocabularyUI

@Suite struct ReviewSessionModelTests {
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
        for (index, term) in ["one", "two", "three"].enumerated() {
            let entry = try words.save(
                WordInsight(term: term, lemma: term, language: .english, nativeLanguage: .turkish, translation: "çeviri",
                            meaning: "Anlam.", source: InsightSource(providerID: "test")),
                captureSource: .text
            )
            // New words come in capture order.
            entry.createdAt = now.addingTimeInterval(Double(index - 10) * 60)
        }
    }

    private func makeSession() throws -> ReviewSessionModel {
        try ReviewSessionModel(language: .english, limits: ReviewLimits(), repository: reviews, calendar: calendar) { [now] in now }
    }

    @Test func showsTheFirstWordHiddenUntilRevealed() throws {
        let session = try makeSession()
        #expect(session.current?.term == "one")
        #expect(!session.isRevealed)
        #expect(session.total == 3)
        session.reveal()
        #expect(session.isRevealed)
    }

    @Test func ratingRecordsTheAnswerAndMovesOn() throws {
        let session = try makeSession()
        let first = try #require(session.current)
        session.reveal()
        session.rate(.good)

        #expect(first.repetitions == 1)
        #expect(session.current?.term == "two")
        #expect(!session.isRevealed)
        #expect(session.finished == 1)
    }

    @Test func aWordAnsweredAgainComesBackAndTheSessionEnds() throws {
        let session = try makeSession()
        session.rate(.again)   // one
        session.rate(.good)    // two
        session.rate(.good)    // three
        #expect(session.current?.term == "one")
        #expect(session.intervalPreview(for: .good) == nil, "Its schedule already changed today")
        session.rate(.good)

        #expect(session.isFinished)
        #expect(session.finished == 3)
        #expect(session.ratings == [.again: 1, .good: 3])
    }

    @Test func previewsTheIntervalEachRatingWouldGive() throws {
        let session = try makeSession()
        #expect(session.intervalPreview(for: .again) == 1)
        #expect(session.intervalPreview(for: .good) == 1)
    }

    @Test func skipsWordsDeletedDuringTheSession() throws {
        let session = try makeSession()
        let second = try #require(try words.entries(language: .english).first { $0.term == "two" })
        try words.delete(second)
        session.rate(.good)
        #expect(session.current?.term == "three")
    }
}
