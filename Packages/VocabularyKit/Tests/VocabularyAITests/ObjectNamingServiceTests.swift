import Foundation
import Testing
import VocabularyCore
@testable import VocabularyAI

@Suite struct ObjectNamingServiceTests {
    private let cupInGerman = ObjectNamingRequest(label: "cup", language: .german, nativeLanguage: .turkish)
    private let tasse = #"{"name":"Tasse","article":"die","translation":"fincan","meaning":"İçecek içmek için kullanılan kulplu küçük kap.","example":"Die Tasse steht auf dem Tisch.","exampleTranslation":"Fincan masanın üstünde duruyor."}"#

    private func service(_ client: ScriptedGenerationClient) -> ObjectNamingService {
        ObjectNamingService(client: client, source: InsightSource(providerID: "apple-on-device"))
    }

    @Test func namesTheObjectWithItsArticle() async throws {
        let insight = try await service(ScriptedGenerationClient([.json(tasse)])).name(cupInGerman)

        #expect(insight.term == "die Tasse")
        #expect(insight.lemma == "Tasse")
        #expect(insight.partOfSpeech == .noun)
        #expect(insight.language == .german && insight.nativeLanguage == .turkish)
        #expect(insight.translation == "fincan")
        #expect(insight.meaning == "İçecek içmek için kullanılan kulplu küçük kap.")
        #expect(insight.examples == [UsageExample(sentence: "Die Tasse steht auf dem Tisch.", translation: "Fincan masanın üstünde duruyor.")])
        #expect(insight.context == nil)
        #expect(insight.source.providerID == "apple-on-device")
    }

    @Test func theArticleIsAChoiceOnlyForLanguagesThatUseOne() async throws {
        let german = ScriptedGenerationClient([.json(tasse)])
        _ = try await service(german).name(cupInGerman)
        let germanCall = try #require(await german.calls.first)
        #expect(germanCall.schemaJSON.contains("\"der\"") && germanCall.schemaJSON.contains("\"das\""))
        #expect(germanCall.request.prompt.contains("cup"))
        #expect(germanCall.request.prompt.contains("German"))

        let english = ScriptedGenerationClient([.json(#"{"name":"cup","translation":"fincan","meaning":"İçecek için küçük bir kap.","example":"The cup is on the table.","exampleTranslation":"Fincan masanın üstünde."}"#)])
        let insight = try await service(english).name(ObjectNamingRequest(label: "cup", language: .english, nativeLanguage: .turkish))
        #expect(insight.term == "cup")
        #expect(await english.calls.first?.schemaJSON.contains("\"article\"") == false)
    }

    @Test func acceptsAnArticleWrittenIntoTheName() async throws {
        let json = #"{"name":"die Tasse","article":"","translation":"fincan","meaning":"Küçük kulplu bir kap.","example":"Ich trinke aus der Tasse.","exampleTranslation":"Fincandan içiyorum."}"#
        let insight = try await service(ScriptedGenerationClient([.json(json)])).name(cupInGerman)
        #expect(insight.term == "die Tasse")
        #expect(insight.lemma == "Tasse")
    }

    @Test func joinsElidedFrenchArticlesWithoutASpace() async throws {
        let json = #"{"name":"ordinateur","article":"l'","translation":"bilgisayar","meaning":"Bilgi işleyen elektronik bir cihaz.","example":"L'ordinateur est sur le bureau.","exampleTranslation":"Bilgisayar masanın üstünde."}"#
        let insight = try await service(ScriptedGenerationClient([.json(json)])).name(ObjectNamingRequest(label: "computer", language: .french, nativeLanguage: .turkish))
        #expect(insight.term == "l'ordinateur")
    }

    @Test func retriesWhenTheArticleIsNotOneOfTheLanguage() async throws {
        let wrong = #"{"name":"Tasse","article":"le","translation":"fincan","meaning":"Küçük kulplu bir kap.","example":"Die Tasse ist voll.","exampleTranslation":"Fincan dolu."}"#
        let client = ScriptedGenerationClient([.json(wrong), .json(tasse)])
        let insight = try await service(client).name(cupInGerman)

        #expect(insight.term == "die Tasse")
        let retry = try #require(await client.calls.last)
        #expect(retry.request.prompt.contains("article"))
    }

    @Test func dropsAnExampleThatDoesNotUseTheWord() async throws {
        let json = #"{"name":"Tasse","article":"die","translation":"fincan","meaning":"Küçük kulplu bir kap.","example":"Ich habe Durst.","exampleTranslation":"Susadım."}"#
        let insight = try await service(ScriptedGenerationClient([.json(json)])).name(cupInGerman)
        #expect(insight.examples.isEmpty)
    }

    @Test func failsWhenTheTranslationIsASentence() async {
        let json = #"{"name":"Tasse","article":"die","translation":"Bu, içecek içmek için kullanılan bir kaptır ve mutfakta durur.","meaning":"Küçük kulplu bir kap.","example":"Die Tasse ist voll.","exampleTranslation":"Fincan dolu."}"#
        await #expect(throws: AIError.self) {
            try await service(ScriptedGenerationClient([.json(json), .json(json)])).name(cupInGerman)
        }
    }
}
