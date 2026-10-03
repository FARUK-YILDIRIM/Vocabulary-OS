import Foundation
import SwiftData
import VocabularyCore

/// A saved word with its insight and review state (SPEC C4).
///
/// CloudKit rules (ADR-002): every property has a default or is optional, relationships are optional
/// with an inverse, and there is no unique constraint. `id` identifies a word across devices; app logic
/// handles duplicates. Arrays are stored as JSON so they sync as plain data.
@Model
public final class VocabularyEntry {
    public var id: UUID = UUID()
    public var term: String = ""
    public var lemma: String = ""
    /// `lemma.matchingKey`, kept in the store for duplicate lookups.
    public var lemmaKey: String = ""
    public var languageCode: String = ""
    public var nativeLanguageCode: String = ""
    public var context: String?
    public var translation: String = ""
    public var meaning: String = ""
    public var partOfSpeechRaw: String?
    public var englishGloss: String?
    public var grammarNote: String?
    public var examplesData: Data?
    public var otherMeaningsData: Data?
    public var insightProviderID: String = ""
    public var insightModelID: String?
    public var insightCreatedAt: Date = Date.now
    public var captureSourceRaw: String = CaptureSource.text.rawValue
    /// Downscaled page or object photo (ADR-005), stored outside the database file.
    @Attribute(.externalStorage) public var imageData: Data?
    public var isFavorite: Bool = false
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    // Review state (ADR-007), mirrored by `cardState`.
    public var ease: Double = 2.5
    public var intervalDays: Int = 0
    public var repetitions: Int = 0
    public var lapses: Int = 0
    public var dueAt: Date = Date.distantPast
    public var lastReviewedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \WordList.entries)
    public var lists: [WordList]? = []

    public init(insight: WordInsight, captureSource: CaptureSource, imageData: Data? = nil) {
        self.captureSourceRaw = captureSource.rawValue
        self.imageData = imageData
        apply(insight)
    }

    /// Replaces the insight fields; review state, favorites and lists stay as they are.
    public func apply(_ insight: WordInsight) {
        term = insight.term
        lemma = insight.lemma
        lemmaKey = insight.lemma.matchingKey
        languageCode = insight.language.rawValue
        nativeLanguageCode = insight.nativeLanguage.rawValue
        context = insight.context
        translation = insight.translation
        meaning = insight.meaning
        partOfSpeechRaw = insight.partOfSpeech?.rawValue
        englishGloss = insight.englishGloss
        grammarNote = insight.grammarNote
        examplesData = try? JSONEncoder().encode(insight.examples)
        otherMeaningsData = try? JSONEncoder().encode(insight.otherMeanings)
        insightProviderID = insight.source.providerID
        insightModelID = insight.source.modelID
        insightCreatedAt = insight.createdAt
        updatedAt = .now
    }

    public var insight: WordInsight {
        WordInsight(
            term: term,
            lemma: lemma,
            partOfSpeech: partOfSpeechRaw.flatMap(PartOfSpeech.init(rawValue:)),
            language: language ?? .english,
            nativeLanguage: LanguageCode(rawValue: nativeLanguageCode) ?? .english,
            context: context,
            translation: translation,
            meaning: meaning,
            englishGloss: englishGloss,
            grammarNote: grammarNote,
            examples: examplesData.flatMap { try? JSONDecoder().decode([UsageExample].self, from: $0) } ?? [],
            otherMeanings: otherMeaningsData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [],
            source: InsightSource(providerID: insightProviderID, modelID: insightModelID),
            createdAt: insightCreatedAt
        )
    }

    public var language: LanguageCode? { LanguageCode(rawValue: languageCode) }

    public var partOfSpeech: PartOfSpeech? { partOfSpeechRaw.flatMap(PartOfSpeech.init(rawValue:)) }

    public var examples: [UsageExample] { insight.examples }

    public var captureSource: CaptureSource {
        get { CaptureSource(rawValue: captureSourceRaw) ?? .text }
        set { captureSourceRaw = newValue.rawValue }
    }

    public var cardState: CardState {
        get {
            CardState(ease: ease, intervalDays: intervalDays, repetitions: repetitions, lapses: lapses, dueAt: dueAt, lastReviewedAt: lastReviewedAt)
        }
        set {
            ease = newValue.ease
            intervalDays = newValue.intervalDays
            repetitions = newValue.repetitions
            lapses = newValue.lapses
            dueAt = newValue.dueAt
            lastReviewedAt = newValue.lastReviewedAt
        }
    }

    public var isNew: Bool { lastReviewedAt == nil }
}
