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
        case "Examples":
            #"{"examples":[{"sentence":"Accept the cookies to continue.","translation":"Devam etmek için çerezleri kabul edin."},{"sentence":"You can delete cookies in your browser settings.","translation":"Çerezleri tarayıcı ayarlarından silebilirsin."}]}"#
        default:
            "{}"
        }
        do {
            return try GeneratedContent(json: json)
        } catch {
            throw .invalidOutput("Stub answer is not valid JSON")
        }
    }
}
#endif
