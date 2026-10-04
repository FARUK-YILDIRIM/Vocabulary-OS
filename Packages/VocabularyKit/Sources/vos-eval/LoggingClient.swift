import Foundation
import FoundationModels
import VocabularyAI

/// Prints each prompt and the model's raw answer (`--verbose`), to see why an answer was rejected.
struct LoggingClient: GenerationClient {
    let base: any GenerationClient

    func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent {
        print("── prompt: \(request.prompt)")
        do {
            let content = try await base.generate(request, schema: schema)
            print("── answer: \(content.jsonString)")
            return content
        } catch {
            print("── error: \(error)")
            throw error
        }
    }
}
