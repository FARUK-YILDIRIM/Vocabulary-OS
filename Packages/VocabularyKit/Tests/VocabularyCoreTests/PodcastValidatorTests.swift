import Foundation
import Testing
@testable import VocabularyCore

@Suite struct PodcastValidatorTests {
    private func word(_ term: String, lemma: String? = nil, _ language: LanguageCode = .english) -> QuizWord {
        QuizWord(id: UUID(), term: term, lemma: lemma ?? term, language: language, nativeLanguage: .turkish,
                 translation: "çeviri", meaning: "")
    }

    private func script(_ lines: [(PodcastSpeaker, String)], title: String = "Am Bahnhof") -> PodcastScript {
        PodcastScript(title: title, segments: lines.map { PodcastSegment(speaker: $0.0, text: $0.1) })
    }

    @Test func findsIrregularAndInflectedForms() {
        let english = script([(.host, "She ran to the station."), (.guest, "The cookies were warm.")])
        #expect(PodcastValidator.missingWords([word("run"), word("cookie")], in: english, language: .english).isEmpty)

        let german = script([(.host, "Die Banken im Park sind neu."), (.guest, "Ich habe meine Schlüssel vergessen.")])
        #expect(PodcastValidator.missingWords([word("Bank", .german), word("Schlüssel", .german)], in: german, language: .german).isEmpty)
    }

    @Test func findsPhrases() {
        let text = script([(.narrator, "Take an umbrella, it is Raining Cats and Dogs today.")])
        #expect(PodcastValidator.missingWords([word("raining cats and dogs")], in: text, language: .english).isEmpty)
    }

    @Test func reportsWordsThatAreMissing() {
        let text = script([(.host, "The train was late."), (.guest, "Yes, very late.")])
        let missing = PodcastValidator.missingWords([word("train"), word("umbrella"), word("pitch")], in: text, language: .english)
        #expect(missing.map(\.term) == ["umbrella", "pitch"])
    }

    @Test func acceptsAWellFormedDialogue() throws {
        let text = script([(.host, "Hallo! Wo ist der Zug?"), (.guest, "Der Zug kommt gleich.")])
        try PodcastValidator.validate(text, words: [word("Zug", .german)], language: .german, style: .dialogue, length: .short)
    }

    @Test(arguments: [
        (PodcastScript(title: "", segments: [PodcastSegment(speaker: .host, text: "Der Zug.")]), PodcastValidator.Problem.missingTitle),
        (PodcastScript(title: "Zug", segments: []), .noSegments),
        (PodcastScript(title: "Zug", segments: [PodcastSegment(speaker: .host, text: "Der Zug."), PodcastSegment(speaker: .guest, text: "  ")]), .emptySegment),
        (PodcastScript(title: "Zug", segments: [PodcastSegment(speaker: .narrator, text: "Der Zug kommt.")]), .wrongSpeakers),
        (PodcastScript(title: "Zug", segments: [PodcastSegment(speaker: .host, text: "Der Zug kommt."), PodcastSegment(speaker: .host, text: "Ja.")]), .wrongSpeakers),
    ])
    func rejectsMalformedDialogues(script: PodcastScript, problem: PodcastValidator.Problem) {
        #expect(throws: problem) {
            try PodcastValidator.validate(script, words: [word("Zug", .german)], language: .german, style: .dialogue, length: .short)
        }
    }

    @Test func storiesAreToldByTheNarrator() {
        let dialogue = script([(.host, "Der Zug kommt."), (.guest, "Gut.")])
        #expect(throws: PodcastValidator.Problem.wrongSpeakers) {
            try PodcastValidator.validate(dialogue, words: [word("Zug", .german)], language: .german, style: .story, length: .short)
        }
    }

    @Test func capsTheLength() {
        let long = Array(repeating: "Der Zug kommt heute später als gestern, und wir warten am Gleis.", count: 60).joined(separator: " ")
        let text = script([(.host, long), (.guest, "Gut.")])
        #expect(throws: PodcastValidator.Problem.tooLong) {
            try PodcastValidator.validate(text, words: [word("Zug", .german)], language: .german, style: .dialogue, length: .short)
        }
    }

    @Test func findsSentencesSaidTwice() {
        let looping = [
            PodcastSegment(speaker: .narrator, text: "Er ist sehr freundlich. Er hat eine Wohnung."),
            PodcastSegment(speaker: .narrator, text: "Er ist sehr freundlich. Er wartet auf den Schlüssel."),
        ]
        #expect(PodcastValidator.repeatsASentence(looping))
        #expect(!PodcastValidator.repeatsASentence([
            PodcastSegment(speaker: .host, text: "Der Zug ist spät."),
            PodcastSegment(speaker: .guest, text: "Ja, wie immer."),
        ]))
        #expect(throws: PodcastValidator.Problem.repeatedSentence) {
            try PodcastValidator.validate(PodcastScript(title: "Zug", segments: looping + [PodcastSegment(speaker: .narrator, text: "Der Zug kommt.")]),
                                          words: [word("Zug", .german)], language: .german, style: .story, length: .short)
        }
    }

    @Test func removesSentencesSaidBefore() {
        let earlier = [PodcastSegment(speaker: .narrator, text: "Er ist sehr freundlich und hilfsbereit.")]
        let part = [
            PodcastSegment(speaker: .narrator, text: "Er ist sehr freundlich und hilfsbereit. Er wartet auf den Zug."),
            PodcastSegment(speaker: .narrator, text: "Er ist sehr freundlich und hilfsbereit."),
        ]
        let cleaned = PodcastValidator.removingRepeatedSentences(from: part, after: earlier)
        #expect(cleaned == [PodcastSegment(speaker: .narrator, text: "Er wartet auf den Zug.")])
    }

    @Test func missingWordsAreAProblem() {
        let text = script([(.host, "Hallo!"), (.guest, "Hallo!")])
        #expect(throws: PodcastValidator.Problem.missingWords(["Zug"])) {
            try PodcastValidator.validate(text, words: [word("Zug", .german)], language: .german, style: .dialogue, length: .short)
        }
    }
}
