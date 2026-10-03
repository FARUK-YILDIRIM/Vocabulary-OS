import Foundation
import SwiftData
import VocabularyCore

/// A named group of words within one learning language (SPEC C4). Deleting a list keeps its words.
@Model
public final class WordList {
    public var id: UUID = UUID()
    public var name: String = ""
    public var languageCode: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var entries: [VocabularyEntry]? = []

    public init(name: String, language: LanguageCode) {
        self.name = name
        self.languageCode = language.rawValue
    }

    public var language: LanguageCode? { LanguageCode(rawValue: languageCode) }
}
