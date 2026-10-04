import Foundation
import FoundationModels
@testable import VocabularyAI

/// A `GenerationClient` that replays scripted JSON answers and records every request, so tests can
/// check both the orchestration and the prompts without a model.
actor ScriptedGenerationClient: GenerationClient {
    enum Reply {
        case json(String)
        case failure(AIError)
    }

    struct Call {
        let request: GenerationRequest
        let schemaJSON: String
    }

    private var replies: [Reply]
    private(set) var calls: [Call] = []
    nonisolated let supportsImages: Bool

    init(_ replies: [Reply], supportsImages: Bool = false) {
        self.replies = replies
        self.supportsImages = supportsImages
    }

    func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent {
        let schemaJSON = (try? JSONEncoder().encode(schema)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        calls.append(Call(request: request, schemaJSON: schemaJSON))
        guard !replies.isEmpty else { throw .unknown("No scripted reply left") }
        switch replies.removeFirst() {
        case .json(let json):
            do {
                return try GeneratedContent(json: json)
            } catch {
                throw .invalidOutput("Scripted reply is not valid JSON")
            }
        case .failure(let error):
            throw error
        }
    }
}
