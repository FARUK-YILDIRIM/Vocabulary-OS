import Foundation
import SwiftData
import VocabularyCore

public enum LibraryFilter: String, CaseIterable, Sendable {
    case all, new, due, favorites, mastered
}

public enum LibrarySort: String, CaseIterable, Sendable {
    case recent, oldest, alphabetical, nextReview
}

/// Reads and writes saved words and lists (SPEC C4).
///
/// Views can use `descriptor(…)` directly with `@Query`, so the library screen and the tests share one
/// definition of every filter.
@MainActor
public final class WordRepository {
    /// Held so the container outlives every use of its context: a `ModelContext` doesn't keep its
    /// container alive, and SwiftData traps when saving into a deallocated one.
    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Words

    @discardableResult
    public func save(_ insight: WordInsight, captureSource: CaptureSource, imageData: Data? = nil) throws -> VocabularyEntry {
        let entry = VocabularyEntry(insight: insight, captureSource: captureSource, imageData: imageData)
        context.insert(entry)
        try context.save()
        return entry
    }

    public func update(_ entry: VocabularyEntry, with insight: WordInsight) throws {
        entry.apply(insight)
        try context.save()
    }

    public func delete(_ entry: VocabularyEntry) throws {
        context.delete(entry)
        try context.save()
    }

    /// The saved word with the same dictionary form in the same language, if any.
    public func existingEntry(lemma: String, language: LanguageCode) throws -> VocabularyEntry? {
        let key = lemma.matchingKey
        let code = language.rawValue
        var descriptor = FetchDescriptor<VocabularyEntry>(predicate: #Predicate { $0.languageCode == code && $0.lemmaKey == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func entries(
        language: LanguageCode,
        filter: LibraryFilter = .all,
        sort: LibrarySort = .recent,
        search: String = "",
        now: Date = .now
    ) throws -> [VocabularyEntry] {
        try context.fetch(Self.descriptor(language: language, filter: filter, sort: sort, search: search, now: now))
    }

    public func count(language: LanguageCode) throws -> Int {
        let code = language.rawValue
        return try context.fetchCount(FetchDescriptor<VocabularyEntry>(predicate: #Predicate { $0.languageCode == code }))
    }

    public static func descriptor(
        language: LanguageCode,
        filter: LibraryFilter = .all,
        sort: LibrarySort = .recent,
        search: String = "",
        now: Date = .now
    ) -> FetchDescriptor<VocabularyEntry> {
        let code = language.rawValue
        let inLanguage = #Predicate<VocabularyEntry> { $0.languageCode == code }
        let matchesFilter = predicate(for: filter, now: now)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchesSearch: Predicate<VocabularyEntry> = query.isEmpty
            ? #Predicate { _ in true }
            : #Predicate {
                $0.term.localizedStandardContains(query)
                    || $0.lemma.localizedStandardContains(query)
                    || $0.translation.localizedStandardContains(query)
            }
        let combined = #Predicate<VocabularyEntry> {
            inLanguage.evaluate($0) && matchesFilter.evaluate($0) && matchesSearch.evaluate($0)
        }
        return FetchDescriptor(predicate: combined, sortBy: sortDescriptors(for: sort))
    }

    private static func predicate(for filter: LibraryFilter, now: Date) -> Predicate<VocabularyEntry> {
        let mastered = CardState.masteredIntervalDays
        switch filter {
        case .all:
            return #Predicate<VocabularyEntry> { _ in true }
        case .new:
            return #Predicate<VocabularyEntry> { $0.lastReviewedAt == nil }
        case .due:
            return #Predicate<VocabularyEntry> { entry in
                entry.lastReviewedAt != nil && entry.dueAt <= now
            }
        case .favorites:
            return #Predicate<VocabularyEntry> { $0.isFavorite }
        case .mastered:
            return #Predicate<VocabularyEntry> { $0.intervalDays >= mastered }
        }
    }

    private static func sortDescriptors(for sort: LibrarySort) -> [SortDescriptor<VocabularyEntry>] {
        switch sort {
        case .recent: [SortDescriptor(\.createdAt, order: .reverse)]
        case .oldest: [SortDescriptor(\.createdAt)]
        case .alphabetical: [SortDescriptor(\.lemmaKey), SortDescriptor(\.createdAt)]
        case .nextReview: [SortDescriptor(\.dueAt), SortDescriptor(\.createdAt)]
        }
    }

    // MARK: Lists

    public func createList(named name: String, language: LanguageCode) throws -> WordList {
        let list = WordList(name: name, language: language)
        context.insert(list)
        try context.save()
        return list
    }

    public func add(_ entry: VocabularyEntry, to list: WordList) {
        guard !(list.entries ?? []).contains(where: { $0.id == entry.id }) else { return }
        list.entries = (list.entries ?? []) + [entry]
        list.updatedAt = .now
    }

    public func remove(_ entry: VocabularyEntry, from list: WordList) {
        list.entries = (list.entries ?? []).filter { $0.id != entry.id }
        list.updatedAt = .now
    }

    public func delete(_ list: WordList) throws {
        context.delete(list)
        try context.save()
    }
}
