import Foundation
import SwiftData
import VocabularyCore

/// Which saved words a quiz asks about (SPEC C8).
public enum QuizSource: Hashable, Sendable, Codable {
    /// Due for review, new words included.
    case due
    case recent
    case favorites
    case all
    case list(UUID)
}

/// A finished quiz, kept for the learner's history (SPEC C8).
///
/// CloudKit rules (ADR-002): every property has a default.
@Model
public final class QuizRecord {
    public var id: UUID = UUID()
    public var languageCode: String = ""
    public var startedAt: Date = Date.now
    public var finishedAt: Date = Date.now
    public var questionCount: Int = 0
    public var correctCount: Int = 0
    /// `QuizSource` as JSON.
    public var sourceData: Data?

    public init(language: LanguageCode, source: QuizSource, startedAt: Date, finishedAt: Date, questionCount: Int, correctCount: Int) {
        self.languageCode = language.rawValue
        self.sourceData = try? JSONEncoder().encode(source)
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.questionCount = questionCount
        self.correctCount = correctCount
    }

    public var source: QuizSource {
        sourceData.flatMap { try? JSONDecoder().decode(QuizSource.self, from: $0) } ?? .all
    }
}
