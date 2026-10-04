import Foundation
import Testing
import VocabularyCore
@testable import VocabularyAI

@Suite struct QuizServiceTests {
    private let bench = QuizWord(id: UUID(), term: "Bank", lemma: "Bank", language: .german, nativeLanguage: .turkish,
                                 translation: "bank", meaning: "Parklarda oturmak için yapılmış uzun oturak.", partOfSpeech: .noun)
    private let key = QuizWord(id: UUID(), term: "Schlüssel", lemma: "Schlüssel", language: .german, nativeLanguage: .turkish,
                               translation: "anahtar", meaning: "Kilidi açmaya yarayan araç.", partOfSpeech: .noun)

    private func service(_ client: ScriptedGenerationClient, strategy: InsightStrategy = .stepwise) -> QuizService {
        QuizService(client: client, strategy: strategy, source: InsightSource(providerID: "apple-on-device"))
    }

    @Test func meaningQuestionsUseTheSavedTranslationAsTheAnswer() async throws {
        let client = ScriptedGenerationClient([.json(#"{"distractors":["tren","elma","kapı"]}"#)])
        let question = try await service(client).question(.meaning, for: bench, library: [])

        #expect(question.kind == .meaning)
        #expect(question.prompt == "Bank")
        #expect(question.correctAnswer == "bank")
        #expect(Set(question.options) == ["bank", "tren", "elma", "kapı"])
        try QuizValidator.validate(question, for: bench)

        let prompt = try #require(await client.calls.first?.request.prompt)
        #expect(prompt.contains("Bank") && prompt.contains("German") && prompt.contains("Turkish"))
    }

    @Test func reverseQuestionsAskForTheWord() async throws {
        let client = ScriptedGenerationClient([.json(#"{"distractors":["Zug","Tisch","Tür"]}"#)])
        let question = try await service(client).question(.reverse, for: bench, library: [])

        #expect(question.prompt == "bank")
        #expect(question.correctAnswer == "Bank")
        try QuizValidator.validate(question, for: bench)
    }

    @Test func clozeQuestionsBlankTheWordInANewSentence() async throws {
        let client = ScriptedGenerationClient([.json(#"{"sentence":"Im Park setzen wir uns auf eine Bank.","distractors":["Zug","Tisch","Tür"]}"#)])
        let question = try await service(client).question(.cloze, for: bench, library: [])

        #expect(question.prompt == "Im Park setzen wir uns auf eine \(QuizValidator.blank).")
        #expect(question.correctAnswer == "Bank")
        try QuizValidator.validate(question, for: bench)
    }

    @Test func retriesWhenADistractorIsTheAnswer() async throws {
        let client = ScriptedGenerationClient([
            .json(#"{"distractors":["bank","tren","elma"]}"#),
            .json(#"{"distractors":["tren","elma","kapı"]}"#),
        ])
        let question = try await service(client).question(.listening, for: bench, library: [])

        #expect(question.correctAnswer == "bank")
        #expect(await client.calls.count == 2)
        #expect(await client.calls.last?.request.prompt.contains("previous answer was not valid") == true)
    }

    @Test func retriesWhenTheClozeSentenceMissesTheWord() async throws {
        let client = ScriptedGenerationClient([
            .json(#"{"sentence":"Wir gehen in den Park.","distractors":["Zug","Tisch","Tür"]}"#),
            .json(#"{"sentence":"Die Bank im Park ist alt.","distractors":["Zug","Tisch","Tür"]}"#),
        ])
        let question = try await service(client).question(.cloze, for: bench, library: [])
        #expect(question.correctAnswer == "Bank")
    }

    @Test func keepsThreeUsableDistractorsWhenTheModelWritesFour() async throws {
        let client = ScriptedGenerationClient([.json(#"{"distractors":["kahve fincanı","tren","elma","kapı"]}"#)])
        let question = try await service(client).question(.meaning, for: QuizWord(
            id: UUID(), term: "Tasse", lemma: "Tasse", language: .german, nativeLanguage: .turkish, translation: "fincan", meaning: ""
        ), library: [])
        #expect(Set(question.options) == ["fincan", "tren", "elma", "kapı"])
    }

    @Test func takesDistractorsFromTheLibraryWithoutAModelCall() async throws {
        let library = [bench, key] + ["Zug": "tren", "Tisch": "masa", "Apfel": "elma"].map { term, translation in
            QuizWord(id: UUID(), term: term, lemma: term, language: .german, nativeLanguage: .turkish, translation: translation, meaning: "")
        }
        let client = ScriptedGenerationClient([])
        let meaning = try await service(client).question(.meaning, for: bench, library: library)
        let reverse = try await service(client).question(.reverse, for: bench, library: library)

        #expect(await client.calls.isEmpty)
        try QuizValidator.validate(meaning, for: bench)
        try QuizValidator.validate(reverse, for: bench)
        #expect(Set(reverse.options).isSubset(of: Set(library.map(\.term))))
    }

    @Test func clozeSentencesComeFromTheModelAndDistractorsFromTheLibrary() async throws {
        let library = [bench, key] + ["Zug", "Tisch", "Apfel"].map { term in
            QuizWord(id: UUID(), term: term, lemma: term, language: .german, nativeLanguage: .turkish, translation: term, meaning: "")
        }
        let client = ScriptedGenerationClient([.json(#"{"sentence":"Die Bank im Park ist alt.","distractors":["Stuhl","Sofa","Hocker","Sessel"]}"#)])
        let question = try await service(client).question(.cloze, for: bench, library: library)

        #expect(question.prompt == "Die \(QuizValidator.blank) im Park ist alt.")
        #expect(Set(question.options).isSubset(of: Set(library.map(\.term))))
    }

    @Test func givesUpAfterTwoInvalidAnswersSoTheCallerCanFallBack() async {
        let wrong = #"{"distractors":["Bank","Banken","Zug"]}"#
        await #expect(throws: AIError.self) {
            try await service(ScriptedGenerationClient([.json(wrong), .json(wrong)])).question(.reverse, for: bench, library: [])
        }
    }

    @Test func cloudModelsWriteAQuizInOneCall() async throws {
        let batch = #"""
        {"items":[
          {"word":1,"meaningDistractors":["tren","elma","kapı"],"termDistractors":["Zug","Tisch","Tür"],"clozeSentence":"Die Bank im Park ist frisch gestrichen."},
          {"word":2,"meaningDistractors":["kilit","kapı","pencere"],"termDistractors":["Schloss","Tür","Fenster"],"clozeSentence":"Wir gehen heute ins Kino."}
        ]}
        """#
        let client = ScriptedGenerationClient([.json(batch)])
        let questions = try await service(client, strategy: .singleCall).questions(for: [
            QuizPlanItem(kind: .meaning, word: bench),
            QuizPlanItem(kind: .cloze, word: bench),
            QuizPlanItem(kind: .reverse, word: key),
            QuizPlanItem(kind: .cloze, word: key),
        ], library: [])

        #expect(await client.calls.count == 1)
        // The second word's sentence doesn't use it, so that cloze question is left to the fallback.
        #expect(questions.map(\.kind) == [.meaning, .cloze, .reverse])
        #expect(questions.map(\.wordID) == [bench.id, bench.id, key.id])
        for (question, word) in zip(questions, [bench, bench, key]) {
            try QuizValidator.validate(question, for: word)
        }
    }
}
