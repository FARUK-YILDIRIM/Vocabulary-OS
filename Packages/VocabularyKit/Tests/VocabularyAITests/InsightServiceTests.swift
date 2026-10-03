import Foundation
import Testing
import VocabularyCore
@testable import VocabularyAI

@Suite struct InsightServiceStepwiseTests {
    private let cookies = InsightRequest(
        term: "cookies",
        sentence: "This website uses cookies for tracking.",
        language: .english,
        nativeLanguage: .turkish
    )

    private let senseJSON = #"{"situation":"a website tracks visitors","englishWord":"cookie","englishGloss":"a small file a website stores to track you","partOfSpeech":"noun"}"#
    private let nativeJSON = #"{"translation":"çerez","meaning":"Web sitelerinin tarayıcıda sakladığı küçük veri dosyası."}"#

    private func service(_ client: ScriptedGenerationClient) -> InsightService {
        InsightService(client: client, strategy: .stepwise, source: InsightSource(providerID: "apple-on-device"))
    }

    @Test func buildsAnInsightFromTheSenseAndNativeSteps() async throws {
        let client = ScriptedGenerationClient([.json(senseJSON), .json(nativeJSON)])
        let insight = try await service(client).insight(for: cookies)

        #expect(insight.term == "cookies")
        #expect(insight.lemma == "cookie") // from NaturalLanguage, not the model
        #expect(insight.partOfSpeech == .noun)
        #expect(insight.translation == "çerez")
        #expect(insight.meaning == "Web sitelerinin tarayıcıda sakladığı küçük veri dosyası.")
        #expect(insight.englishGloss == "a small file a website stores to track you")
        #expect(insight.language == .english && insight.nativeLanguage == .turkish)
        #expect(insight.source.providerID == "apple-on-device")
        #expect(insight.examples.isEmpty)
    }

    @Test func promptsMarkTheTermAndNameTheLanguages() async throws {
        let client = ScriptedGenerationClient([.json(senseJSON), .json(nativeJSON)])
        _ = try await service(client).insight(for: cookies)
        let calls = await client.calls

        #expect(calls.count == 2)
        #expect(calls[0].request.prompt.contains("«cookies»"))
        #expect(calls[0].request.prompt.contains("English"))
        #expect(calls[0].request.isGreedy)
        #expect(calls[1].request.instructions.contains("Turkish"))
        #expect(calls[1].schemaJSON.contains("Turkish"))
        #expect(calls[1].request.prompt.contains("a small file a website stores to track you"))
    }

    @Test func englishNativeSpeakersNeedOnlyTheSenseStep() async throws {
        let request = InsightRequest(
            term: "abzuheben", sentence: "Ich muss zur Bank, um Geld abzuheben.", language: .german, nativeLanguage: .english
        )
        let client = ScriptedGenerationClient([
            .json(#"{"situation":"someone goes to a bank","englishWord":"withdraw","englishGloss":"to take money out of an account","partOfSpeech":"verb"}"#),
        ])
        let insight = try await service(client).insight(for: request)

        #expect(await client.calls.count == 1)
        #expect(insight.translation == "withdraw")
        #expect(insight.meaning == "to take money out of an account")
        // No German lemma scheme on device, so the term itself is kept for the learner to edit.
        #expect(insight.lemma == "abzuheben")
    }

    @Test func retriesOnceWhenTheTranslationIsASentence() async throws {
        let client = ScriptedGenerationClient([
            .json(senseJSON),
            .json(#"{"translation":"Bu web sitesi izleme için çerez kullanır ve bunu herkes bilir.","meaning":"Küçük veri dosyası."}"#),
            .json(nativeJSON),
        ])
        let insight = try await service(client).insight(for: cookies)
        let calls = await client.calls

        #expect(insight.translation == "çerez")
        #expect(calls.count == 3)
        #expect(calls[2].request.prompt.contains("previous answer"))
        #expect(!calls[2].request.isGreedy)
    }

    @Test func failsAfterTheRetryIsAlsoInvalid() async {
        let wrongLanguage = #"{"translation":"cookie","meaning":"A small data file that websites store in the browser."}"#
        let client = ScriptedGenerationClient([.json(senseJSON), .json(wrongLanguage), .json(wrongLanguage)])
        await #expect(throws: AIError.self) {
            try await service(client).insight(for: cookies)
        }
    }

    @Test func retriesAfterADecodingFailure() async throws {
        let client = ScriptedGenerationClient([
            .failure(.invalidOutput("truncated")), .json(senseJSON), .json(nativeJSON),
        ])
        let insight = try await service(client).insight(for: cookies)
        #expect(insight.translation == "çerez")
    }

    @Test func doesNotRetryWhenTheModelIsUnavailable() async {
        let client = ScriptedGenerationClient([.failure(.onDeviceUnavailable(.appleIntelligenceNotEnabled))])
        await #expect(throws: AIError.onDeviceUnavailable(.appleIntelligenceNotEnabled)) {
            try await service(client).insight(for: cookies)
        }
        #expect(await client.calls.count == 1)
    }

    @Test func explainsTheCommonMeaningWhenThereIsNoSentence() async throws {
        let request = InsightRequest(term: "cookie", sentence: nil, language: .english, nativeLanguage: .turkish)
        let client = ScriptedGenerationClient([
            .json(#"{"englishWord":"cookie","englishGloss":"a small sweet baked biscuit","partOfSpeech":"noun"}"#),
            .json(#"{"translation":"kurabiye","meaning":"Fırında pişirilen küçük tatlı."}"#),
        ])
        let insight = try await service(client).insight(for: request)
        let calls = await client.calls

        #expect(insight.translation == "kurabiye")
        #expect(insight.context == nil)
        #expect(calls[0].request.prompt.contains("No sentence"))
        #expect(!calls[0].schemaJSON.contains("situation"))
    }

    @Test func examplesKeepOnlySentencesThatUseTheTerm() async throws {
        let base = try await service(ScriptedGenerationClient([.json(senseJSON), .json(nativeJSON)])).insight(for: cookies)
        let client = ScriptedGenerationClient([
            .json(#"{"examples":[{"sentence":"Accept the cookies to continue.","translation":"Devam etmek için çerezleri kabul edin."},{"sentence":"The politician gave a speech.","translation":"Politikacı bir konuşma yaptı."}]}"#),
        ])
        let detailed = try await service(client).addingExamples(to: base)

        #expect(detailed.examples == [UsageExample(sentence: "Accept the cookies to continue.", translation: "Devam etmek için çerezleri kabul edin.")])
    }
}

@Suite struct InsightServiceSingleCallTests {
    @Test func cloudModelsReturnTheFullEntryInOneCall() async throws {
        let request = InsightRequest(
            term: "Schlüssel", sentence: "Ich habe meinen Schlüssel im Büro vergessen.", language: .german, nativeLanguage: .turkish
        )
        let client = ScriptedGenerationClient([.json("""
        {"lemma":"Schlüssel","partOfSpeech":"noun","englishGloss":"a metal tool that opens a lock",
         "translation":"anahtar","meaning":"Kilidi açmaya yarayan metal araç.","grammarNote":"der Schlüssel, die Schlüssel",
         "examples":[{"sentence":"Wo ist mein Schlüssel?","translation":"Anahtarım nerede?"},
                     {"sentence":"Der Schlüssel passt nicht.","translation":"Anahtar uymuyor."}],
         "otherMeanings":["şifre anahtarı","şifre anahtarı","nota anahtarı","anahtar"]}
        """)])
        let service = InsightService(client: client, strategy: .singleCall, source: InsightSource(providerID: "openai", modelID: "gpt-6-luna"))
        let insight = try await service.insight(for: request)

        #expect(await client.calls.count == 1)
        #expect(insight.lemma == "Schlüssel")
        #expect(insight.grammarNote == "der Schlüssel, die Schlüssel")
        #expect(insight.examples.count == 2)
        // Duplicates and the translation itself are dropped.
        #expect(insight.otherMeanings == ["şifre anahtarı", "nota anahtarı"])
        #expect(insight.source == InsightSource(providerID: "openai", modelID: "gpt-6-luna"))
    }
}

@Suite struct InsightValidatorTests {
    @Test(arguments: ["«çerez»", "\"çerez\"", "  çerez. "])
    func cleansQuotesAndPunctuationFromTranslations(_ raw: String) {
        #expect(InsightValidator.cleanTranslation(raw) == "çerez")
    }

    @Test func rejectsTextThatIsConfidentlyInAnotherLanguage() {
        #expect(!InsightValidator.isPlausibly("A small data file that websites store in the browser.", in: .turkish))
        #expect(InsightValidator.isPlausibly("Web sitelerinin tarayıcıda sakladığı küçük veri dosyası.", in: .turkish))
        // Too short to judge: accepted.
        #expect(InsightValidator.isPlausibly("bank", in: .turkish))
    }
}
