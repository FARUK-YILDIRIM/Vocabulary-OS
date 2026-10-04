import Foundation
import Testing
@testable import VocabularyCore

@Suite struct WordOccurrencesTests {
    private func word(_ term: String, lemma: String? = nil, _ language: LanguageCode = .english) -> QuizWord {
        QuizWord(id: UUID(), term: term, lemma: lemma ?? term, language: language, nativeLanguage: .turkish,
                 translation: "çeviri", meaning: "")
    }

    private func found(_ matches: [WordOccurrences.Match], in text: String) -> [String] {
        matches.map { String(text[$0.range]) }
    }

    @Test func findsEveryFormOfAWordInReadingOrder() {
        let run = word("run")
        let cookie = word("cookies", lemma: "cookie")
        let text = "She ran home. The cookie was warm, and two cookies were left."
        let matches = WordOccurrences.find([cookie, run], in: text, language: .english)
        #expect(found(matches, in: text) == ["ran", "cookie", "cookies"])
        #expect(matches.map(\.wordID) == [run.id, cookie.id, cookie.id])
    }

    @Test func findsInflectedGermanNouns() {
        let text = "Die Banken im Park sind neu."
        #expect(found(WordOccurrences.find([word("Bank", .german)], in: text, language: .german), in: text) == ["Banken"])
    }

    @Test func findsPhrasesIgnoringCaseAndAccents() {
        let text = "It is Raining Cats and Dogs. Yes, raining cats and dogs!"
        let matches = WordOccurrences.find([word("raining cats and dogs")], in: text, language: .english)
        #expect(found(matches, in: text) == ["Raining Cats and Dogs", "raining cats and dogs"])
    }

    @Test func highlightsDontOverlap() {
        let phrase = word("raining cats and dogs")
        let dogs = word("dogs")
        let text = "It is raining cats and dogs, and the dogs are wet."
        #expect(WordOccurrences.find([phrase, dogs], in: text, language: .english).count == 3)

        let highlights = WordOccurrences.highlights([phrase, dogs], in: text, language: .english)
        #expect(found(highlights, in: text) == ["raining cats and dogs", "dogs"])
        #expect(highlights.map(\.wordID) == [phrase.id, dogs.id])
    }

    @Test func findsNothingWithoutTheWord() {
        #expect(WordOccurrences.find([word("umbrella")], in: "The train was late.", language: .english).isEmpty)
    }
}
