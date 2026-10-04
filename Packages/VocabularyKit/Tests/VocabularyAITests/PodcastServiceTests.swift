import Foundation
import Testing
import VocabularyCore
@testable import VocabularyAI

@Suite struct PodcastServiceTests {
    private func word(_ term: String) -> QuizWord {
        QuizWord(id: UUID(), term: term, lemma: term, language: .german, nativeLanguage: .turkish, translation: term, meaning: "")
    }

    private var request: PodcastRequest {
        PodcastRequest(words: [word("Zug"), word("Bank"), word("Tasse")], language: .german, nativeLanguage: .turkish,
                       level: .a2, length: .short, style: .dialogue)
    }

    /// Parts without a word of their own: a short episode has six parts, three of them for these
    /// three words.
    private let fillers: [ScriptedGenerationClient.Reply] = [
        .json(#"{"lines":[{"speaker":"host","text":"Wie war deine Woche?"},{"speaker":"guest","text":"Sehr ruhig, danke."}]}"#),
        .json(#"{"lines":[{"speaker":"host","text":"Hast du Pläne für morgen?"},{"speaker":"guest","text":"Ich gehe einkaufen."}]}"#),
        .json(#"{"lines":[{"speaker":"host","text":"Bis zum nächsten Mal!"},{"speaker":"guest","text":"Tschüss!"}]}"#),
    ]
    private let fillerLines = ["Wie war deine Woche?", "Sehr ruhig, danke.", "Hast du Pläne für morgen?", "Ich gehe einkaufen.", "Bis zum nächsten Mal!", "Tschüss!"]

    private func service(_ client: ScriptedGenerationClient, _ strategy: InsightStrategy) -> PodcastService {
        PodcastService(client: client, strategy: strategy, source: InsightSource(providerID: "test"))
    }

    @Test func cloudModelsWriteTheScriptInOneCall() async throws {
        let json = #"{"title":"Am Bahnhof","lines":[{"speaker":"host","text":"Der Zug kommt gleich."},{"speaker":"guest","text":"Ich warte auf der Bank mit einer Tasse Tee."}]}"#
        let client = ScriptedGenerationClient([.json(json)])
        let script = try await service(client, .singleCall).script(for: request)

        #expect(script.title == "Am Bahnhof")
        #expect(script.segments.map(\.speaker) == [.host, .guest])
        #expect(await client.calls.count == 1)
        let call = try #require(await client.calls.first)
        #expect(call.request.prompt.contains("«Zug»") && call.request.prompt.contains("«Tasse»"))
        #expect(call.request.instructions.contains("A2"))
    }

    @Test func aScriptMissingAWordIsAskedForAgain() async throws {
        let missing = #"{"title":"Am Bahnhof","lines":[{"speaker":"host","text":"Der Zug kommt."},{"speaker":"guest","text":"Gut."}]}"#
        let complete = #"{"title":"Am Bahnhof","lines":[{"speaker":"host","text":"Der Zug kommt."},{"speaker":"guest","text":"Ich sitze auf der Bank mit einer Tasse."}]}"#
        let client = ScriptedGenerationClient([.json(missing), .json(complete)])
        let script = try await service(client, .singleCall).script(for: request)

        #expect(script.segments.count == 2)
        #expect(await client.calls.last?.request.prompt.contains("Bank") == true)
    }

    @Test func theOnDeviceModelWritesEnoughPartsForTheLength() async throws {
        let first = #"{"title":"Am Bahnhof","lines":[{"speaker":"host","text":"Hallo! Der Zug ist spät."},{"speaker":"guest","text":"Dann warten wir."}]}"#
        let second = #"{"lines":[{"speaker":"host","text":"Setzen wir uns auf die Bank?"},{"speaker":"guest","text":"Gute Idee."}]}"#
        let third = #"{"lines":[{"speaker":"host","text":"Möchtest du eine Tasse Tee?"},{"speaker":"guest","text":"Ja, gern. Bis bald!"}]}"#
        let client = ScriptedGenerationClient([.json(first), .json(second), .json(third)] + fillers)
        let script = try await service(client, .stepwise).script(for: request)

        #expect(script.title == "Am Bahnhof")
        #expect(script.segments.count == 12)
        let calls = await client.calls
        #expect(calls.count == 6, "About two minutes take six parts, though there are three words")
        #expect(calls[0].request.prompt.contains("part 1 of 6") && calls[0].request.prompt.contains("use the German word «Zug»"))
        #expect(calls[1].request.prompt.contains("part 2 of 6") && calls[1].request.prompt.contains("«Bank»"))
        #expect(!calls[3].request.prompt.contains("In this part"), "Parts after the words have none of their own")
        #expect(calls[0].request.prompt.contains("«Tasse»"), "The first part sees every word, to choose a topic")
        #expect(calls[1].request.prompt.contains("«Am Bahnhof»"), "Later parts know the episode's title")
        #expect(calls[5].request.prompt.contains("End the episode."))
        #expect(calls[2].request.prompt.contains("Don't end the episode yet."))
        #expect(!calls[0].request.isGreedy, "Greedy decoding repeats itself in longer text")
        // Only the first part writes the title.
        #expect(calls[0].schemaJSON.contains("A short German title for the episode."))
        #expect(!calls[1].schemaJSON.contains("title for the episode."))
    }

    /// Enough parts for about 130 words a minute, at least one per word, within each length's limit.
    @Test func partsFollowTheLength() {
        var long = request
        long.length = .long
        #expect(PodcastPrompts.partCount(for: request) == 6)
        #expect(PodcastPrompts.partCount(for: long) == 14)
        long.words = (1...12).map { word("Wort\($0)") }
        #expect(PodcastPrompts.partCount(for: long) == 14)
    }

    @Test func aWordTheDraftLeftOutGetsALineOfItsOwn() async throws {
        let first = #"{"title":"Am Bahnhof","lines":[{"speaker":"host","text":"Der Zug ist spät."},{"speaker":"guest","text":"Leider."}]}"#
        let withoutBank = #"{"lines":[{"speaker":"host","text":"Schönes Wetter heute."},{"speaker":"guest","text":"Ja, sehr schön."}]}"#
        let third = #"{"lines":[{"speaker":"host","text":"Eine Tasse Kaffee?"},{"speaker":"guest","text":"Gern!"}]}"#
        let line = #"{"sentence":"Setzen wir uns auf die Bank dort."}"#
        let client = ScriptedGenerationClient([.json(first), .json(withoutBank), .json(third)] + fillers + [.json(line)])
        let script = try await service(client, .stepwise).script(for: request)

        // The line joins the part meant for the word, from the other host.
        #expect(script.segments.map(\.text) == [
            "Der Zug ist spät.", "Leider.", "Schönes Wetter heute.", "Ja, sehr schön.", "Setzen wir uns auf die Bank dort.",
            "Eine Tasse Kaffee?", "Gern!",
        ] + fillerLines)
        #expect(script.segments[4].speaker == .host)
        let calls = await client.calls
        #expect(calls.count == 7)
        #expect(calls[6].request.prompt.contains("«Bank»") && calls[6].request.prompt.contains("«Am Bahnhof»"))
    }

    /// The model's safety rules sometimes stop an ordinary part (seen in `vos-eval podcast`); the part
    /// is left out, and its word gets a line of its own.
    @Test func aPartTheModelStopsIsLeftOut() async throws {
        let first = #"{"title":"Am Bahnhof","lines":[{"speaker":"host","text":"Der Zug ist spät."},{"speaker":"guest","text":"Leider."}]}"#
        let third = #"{"lines":[{"speaker":"host","text":"Eine Tasse Kaffee?"},{"speaker":"guest","text":"Gern!"}]}"#
        let line = #"{"sentence":"Setzen wir uns auf die Bank dort."}"#
        let client = ScriptedGenerationClient([.json(first), .failure(.guardrailViolation), .json(third)] + fillers + [.json(line)])
        let script = try await service(client, .stepwise).script(for: request)

        #expect(script.segments.contains { $0.text == "Setzen wir uns auf die Bank dort." })
        try PodcastValidator.validate(script, words: request.words, language: .german, style: .dialogue, length: .short)
    }

    /// Without a first part there is no title yet, so the next part writes it.
    @Test func theTitleComesFromTheFirstPartWritten() async throws {
        let second = #"{"title":"Im Park","lines":[{"speaker":"host","text":"Wir sitzen auf der Bank."},{"speaker":"guest","text":"Bequem!"}]}"#
        let third = #"{"lines":[{"speaker":"host","text":"Eine Tasse Kaffee?"},{"speaker":"guest","text":"Gern!"}]}"#
        let line = #"{"sentence":"Der Zug kommt bald."}"#
        let client = ScriptedGenerationClient([.failure(.guardrailViolation), .json(second), .json(third)] + fillers + [.json(line)])
        let script = try await service(client, .stepwise).script(for: request)

        #expect(script.title == "Im Park")
        #expect(await client.calls[1].schemaJSON.contains("title for the episode."))
    }

    @Test func aLineThatMissesTheWordIsAskedForAgain() async throws {
        let first = #"{"title":"Am Bahnhof","lines":[{"speaker":"host","text":"Der Zug ist spät."},{"speaker":"guest","text":"Leider."}]}"#
        let withoutBank = #"{"lines":[{"speaker":"host","text":"Schönes Wetter heute."},{"speaker":"guest","text":"Ja, sehr schön."}]}"#
        let third = #"{"lines":[{"speaker":"host","text":"Eine Tasse Kaffee?"},{"speaker":"guest","text":"Gern!"}]}"#
        let client = ScriptedGenerationClient([
            .json(first), .json(withoutBank), .json(third),
        ] + fillers + [
            .json(#"{"sentence":"Wir sitzen im Park."}"#), .json(#"{"sentence":"Die Bank ist frei."}"#),
        ])
        let script = try await service(client, .stepwise).script(for: request)
        #expect(script.segments.contains { $0.text == "Die Bank ist frei." })
    }

    @Test func sentencesSaidBeforeAreDropped() async throws {
        let first = #"{"title":"Am Bahnhof","lines":[{"speaker":"host","text":"Der Zug ist heute spät."},{"speaker":"guest","text":"Wie immer."}]}"#
        let looping = #"{"lines":[{"speaker":"host","text":"Der Zug ist heute spät."},{"speaker":"guest","text":"Wir sitzen auf der Bank."}]}"#
        let third = #"{"lines":[{"speaker":"host","text":"Eine Tasse Kaffee?"},{"speaker":"guest","text":"Gern!"}]}"#
        let line = #"{"sentence":"Dort drüben ist eine Bank frei."}"#
        let client = ScriptedGenerationClient([.json(first), .json(looping), .json(third)] + fillers + [.json(line)])
        let script = try await service(client, .stepwise).script(for: request)

        #expect(script.segments.filter { $0.text == "Der Zug ist heute spät." }.count == 1)
        try PodcastValidator.validate(script, words: request.words, language: .german, style: .dialogue, length: .short)
    }

    @Test func aPartLongerThanItsShareLosesItsLastLines() {
        let part = PodcastScript(title: "Zug", segments: [
            PodcastSegment(speaker: .host, text: "Der Zug kommt gleich am Gleis drei an."),
            PodcastSegment(speaker: .guest, text: "Gut. Dann haben wir noch Zeit für einen Kaffee am Kiosk."),
        ])
        let trimmed = PodcastParser.trimmed(part, toWordLimit: 10)
        #expect(trimmed.segments.map(\.text) == ["Der Zug kommt gleich am Gleis drei an.", "Gut."])
        #expect(PodcastParser.trimmed(part, toWordLimit: 3).segments.map(\.text) == ["Der Zug kommt gleich am Gleis drei an."])
    }

    @Test func theLastAttemptKeepsATitleThatListsTheWords() async throws {
        let listing = #"{"title":"Zug, Bank und Tasse","lines":[{"speaker":"host","text":"Der Zug ist spät."},{"speaker":"guest","text":"Leider."}]}"#
        let second = #"{"lines":[{"speaker":"host","text":"Wir sitzen auf der Bank."},{"speaker":"guest","text":"Bequem!"}]}"#
        let third = #"{"lines":[{"speaker":"host","text":"Eine Tasse Kaffee?"},{"speaker":"guest","text":"Gern!"}]}"#
        let client = ScriptedGenerationClient([.json(listing), .json(listing), .json(listing), .json(second), .json(third)] + fillers)
        let script = try await service(client, .stepwise).script(for: request)
        #expect(script.title == "Zug, Bank und Tasse")
    }

    @Test func aTitleThatListsTheWordsIsAskedForAgain() async throws {
        let listing = #"{"title":"Zug, Bank und Tasse","lines":[{"speaker":"host","text":"Der Zug ist spät."},{"speaker":"guest","text":"Leider."}]}"#
        let first = #"{"title":"Am Bahnhof","lines":[{"speaker":"host","text":"Der Zug ist spät."},{"speaker":"guest","text":"Leider."}]}"#
        let second = #"{"lines":[{"speaker":"host","text":"Wir sitzen auf der Bank."},{"speaker":"guest","text":"Bequem!"}]}"#
        let third = #"{"lines":[{"speaker":"host","text":"Eine Tasse Kaffee?"},{"speaker":"guest","text":"Gern!"}]}"#
        let client = ScriptedGenerationClient([.json(listing), .json(first), .json(second), .json(third)] + fillers)
        let script = try await service(client, .stepwise).script(for: request)

        #expect(script.title == "Am Bahnhof")
        #expect(await client.calls[1].request.prompt.contains("not list the words"))
    }

    /// The on-device model sometimes titled a German episode in English.
    @Test func aTitleInAnotherLanguageIsAskedForAgain() async throws {
        let english = #"{"title":"A Day at the Train Station","lines":[{"speaker":"host","text":"Der Zug ist spät."},{"speaker":"guest","text":"Leider."}]}"#
        let german = #"{"title":"Ein langer Tag am Bahnhof","lines":[{"speaker":"host","text":"Der Zug ist spät."},{"speaker":"guest","text":"Leider."}]}"#
        let second = #"{"lines":[{"speaker":"host","text":"Wir sitzen auf der Bank."},{"speaker":"guest","text":"Bequem!"}]}"#
        let third = #"{"lines":[{"speaker":"host","text":"Eine Tasse Kaffee?"},{"speaker":"guest","text":"Gern!"}]}"#
        let client = ScriptedGenerationClient([.json(english), .json(german), .json(second), .json(third)] + fillers)
        let script = try await service(client, .stepwise).script(for: request)

        #expect(script.title == "Ein langer Tag am Bahnhof")
        #expect(await client.calls[1].request.prompt.contains("the title must be in German"))
    }

    /// Two words are too few to tell a language by.
    @Test func shortTitlesAreNotJudgedByLanguage() throws {
        try PodcastParser.checkTitle("Am Bahnhof", words: request.words, language: .german)
        try PodcastParser.checkTitle("Hotel Paradiso", words: request.words, language: .german)
    }

    @Test func storiesAreToldInParagraphsByTheNarrator() async throws {
        var story = request
        story.style = .story
        let first = #"{"title":"Die Reise","paragraphs":["Der Zug fährt ab. Alle winken."]}"#
        let second = #"{"paragraphs":["Anna sitzt auf einer Bank. Sie wartet."]}"#
        let third = #"{"paragraphs":["Sie trinkt eine Tasse Tee und lacht."]}"#
        let more: [ScriptedGenerationClient.Reply] = [
            .json(#"{"paragraphs":["Der Abend kommt langsam."]}"#),
            .json(#"{"paragraphs":["Die Lichter gehen an."]}"#),
            .json(#"{"paragraphs":["Am Ende ist Anna froh."]}"#),
        ]
        let script = try await service(ScriptedGenerationClient([.json(first), .json(second), .json(third)] + more), .stepwise).script(for: story)

        #expect(script.segments.count == 6)
        #expect(script.segments.allSatisfy { $0.speaker == .narrator })
        try PodcastValidator.validate(script, words: story.words, language: .german, style: .story, length: .short)
    }
}
