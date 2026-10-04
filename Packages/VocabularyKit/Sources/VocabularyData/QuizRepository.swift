import Foundation
import SwiftData
import VocabularyCore

/// Words for quizzes, and the results of finished quizzes (SPEC C8).
@MainActor
public final class QuizRepository {
    /// Wrong answers come from the learner's other words, so a quiz needs at least this many.
    public static let minimumWords = 4

    private let words: WordRepository
    private var context: ModelContext { words.context }

    public init(words: WordRepository) {
        self.words = words
    }

    /// Up to `limit` words from the source. Due words come most overdue first, recent ones newest
    /// first; favorites, lists and all words are shuffled.
    public func words(language: LanguageCode, source: QuizSource, limit: Int, now: Date = .now) throws -> [VocabularyEntry] {
        let picked: [VocabularyEntry]
        switch source {
        case .due:
            // New words are due from the distant past, so they come along.
            picked = try words.entries(language: language, sort: .nextReview, now: now).filter { $0.cardState.isDue(at: now) }
        case .recent:
            picked = try words.entries(language: language, sort: .recent, now: now)
        case .favorites:
            picked = try words.entries(language: language, filter: .favorites, now: now).shuffled()
        case .all:
            picked = try words.entries(language: language, now: now).shuffled()
        case .list(let id):
            var descriptor = FetchDescriptor<WordList>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let list = try context.fetch(descriptor).first
            picked = (list?.entries ?? []).filter { $0.language == language }.shuffled()
        }
        return Array(picked.prefix(max(0, limit)))
    }

    /// Every saved word, the source of wrong answers.
    public func library() throws -> [VocabularyEntry] {
        try context.fetch(FetchDescriptor<VocabularyEntry>())
    }

    public func save(_ record: QuizRecord) throws {
        context.insert(record)
        try context.save()
    }

    /// Finished quizzes in one language, newest first.
    public func records(language: LanguageCode) throws -> [QuizRecord] {
        let code = language.rawValue
        return try context.fetch(FetchDescriptor<QuizRecord>(
            predicate: #Predicate { $0.languageCode == code },
            sortBy: [SortDescriptor(\.finishedAt, order: .reverse)]
        ))
    }
}

extension VocabularyEntry {
    /// The word as a quiz sees it.
    public var quizWord: QuizWord {
        QuizWord(
            id: id,
            term: term,
            lemma: lemma,
            language: language ?? .english,
            nativeLanguage: LanguageCode(rawValue: nativeLanguageCode) ?? .english,
            translation: translation,
            meaning: meaning,
            context: context,
            partOfSpeech: partOfSpeechRaw.flatMap(PartOfSpeech.init(rawValue:))
        )
    }
}
