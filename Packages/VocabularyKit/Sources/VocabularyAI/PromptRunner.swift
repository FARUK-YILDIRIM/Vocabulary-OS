import Foundation
import FoundationModels

/// Why a validator rejected an answer. The reason goes back to the model in the retry prompt, so it
/// is written as an instruction and never quotes the learner's text.
struct ValidationFailure: Error {
    let reason: String
}

extension PromptSpec {
    /// Runs the prompt, retrying once when the answer is unreadable or rejected by the validator.
    func run<Output>(
        on client: any GenerationClient,
        validate: (GeneratedContent) throws(ValidationFailure) -> Output
    ) async throws(AIError) -> Output {
        var current = self
        var lastError = AIError.invalidOutput("No answer")
        for _ in 0..<2 {
            let content: GeneratedContent
            do {
                content = try await client.generate(current.request, schema: current.schema)
            } catch where error.isWorthRetrying {
                lastError = error
                current = retry(reason: nil)
                continue
            }
            do {
                return try validate(content)
            } catch {
                lastError = .invalidOutput(error.reason)
                current = retry(reason: error.reason)
            }
        }
        throw lastError
    }
}
