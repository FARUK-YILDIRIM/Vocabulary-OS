import Foundation
import FoundationModels

/// Why a validator rejected an answer. The reason goes back to the model in the retry prompt, so it
/// is written as an instruction and never quotes the learner's text.
struct ValidationFailure: Error {
    let reason: String
}

extension PromptSpec {
    /// Runs the prompt, retrying when the answer is unreadable or rejected by the validator: once by
    /// default, more often for long creative text that fails more easily.
    func run<Output>(
        on client: any GenerationClient,
        attempts: Int = 2,
        validate: (GeneratedContent) throws(ValidationFailure) -> Output
    ) async throws(AIError) -> Output {
        var current = self
        var lastError = AIError.invalidOutput("No answer")
        for _ in 0..<max(1, attempts) {
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
