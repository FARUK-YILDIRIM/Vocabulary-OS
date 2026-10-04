#if DEBUG
import Foundation
import FoundationModels
import VocabularyAI

/// Canned AI answers for UI tests (`-vos-ai-stub YES`), so they run the same everywhere, with or
/// without Apple Intelligence. Answers are picked by the schema's name.
struct StubGenerationClient: GenerationClient {
    func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent {
        try? await Task.sleep(for: .milliseconds(300))
        let title = (try? JSONEncoder().encode(schema))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { $0["title"] as? String } ?? ""
        let json = switch title {
        case "Sense":
            #"{"situation":"a website tracks visitors","englishWord":"cookie","englishGloss":"a small file a website stores in the browser","partOfSpeech":"noun"}"#
        case "Explanation":
            #"{"translation":"çerez","meaning":"Web sitelerinin tarayıcıda sakladığı küçük veri dosyası."}"#
        case "ObjectName":
            #"{"name":"Tasse","article":"die","translation":"fincan","meaning":"İçecek içmek için kullanılan kulplu küçük kap.","example":"Die Tasse steht auf dem Tisch.","exampleTranslation":"Fincan masanın üstünde duruyor."}"#
        case "Examples":
            #"{"examples":[{"sentence":"Accept the cookies to continue.","translation":"Devam etmek için çerezleri kabul edin."},{"sentence":"You can delete cookies in your browser settings.","translation":"Çerezleri tarayıcı ayarlarından silebilirsin."}]}"#
        case "PodcastScript", "PodcastPart":
            Self.podcastPart(for: request.prompt)
        case "PodcastLine":
            Self.podcastLine(for: request.prompt)
        default:
            "{}"
        }
        do {
            return try GeneratedContent(json: json)
        } catch {
            throw .invalidOutput("Stub answer is not valid JSON")
        }
    }

    /// Different sentences for every part, since repeated sentences are dropped; dialogue lines and
    /// story paragraphs both, since the schema name doesn't tell the style.
    private static func podcastPart(for prompt: String) -> String {
        let part = prompt.firstMatch(of: /part (\d+) of/)?.1 ?? "1"
        return json([
            "title": "A Day in Town",
            "lines": [
                ["speaker": "host", "text": "This is part \(part) of our little show."],
                ["speaker": "guest", "text": "I am glad to talk with you in part \(part)."],
            ],
            "paragraphs": ["Part \(part) of the story begins on a quiet morning."],
        ])
    }

    /// A sentence with the word the prompt asks for, which the drafts above never use.
    private static func podcastLine(for prompt: String) -> String {
        let word = prompt.matches(of: /«([^»]+)»/).last.map { String($0.1) } ?? "word"
        return json(["sentence": "Today we often say \(word) in town."])
    }

    private static func json(_ object: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: object)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
#endif
