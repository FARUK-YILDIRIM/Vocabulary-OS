import Foundation
import FoundationModels

/// One generation task: who the model is (instructions), what to do (prompt) and how to sample.
public struct GenerationRequest: Sendable, Hashable {
    public var instructions: String
    public var prompt: String
    /// Greedy decoding gives repeatable answers; use it for lookups, not for creative text.
    public var isGreedy: Bool
    public var temperature: Double?
    /// Always set: on device, the 4,096-token context holds instructions, schema, prompt and output.
    public var maximumResponseTokens: Int

    public init(
        instructions: String,
        prompt: String,
        isGreedy: Bool = true,
        temperature: Double? = nil,
        maximumResponseTokens: Int = 500
    ) {
        self.instructions = instructions
        self.prompt = prompt
        self.isGreedy = isGreedy
        self.temperature = temperature
        self.maximumResponseTokens = maximumResponseTokens
    }
}

/// A model that produces structured output for a schema (ADR-003).
///
/// Outputs are defined once as `@Generable` types. The on-device client uses guided generation with
/// the schema directly; cloud clients send the schema as JSON Schema and parse the reply back into
/// `GeneratedContent`.
public protocol GenerationClient: Sendable {
    func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent
}

extension GenerationClient {
    /// Generates a value of a `@Generable` type.
    public func generate<Output: Generable>(_ request: GenerationRequest, as type: Output.Type) async throws(AIError) -> Output {
        let content = try await generate(request, schema: Output.generationSchema)
        do {
            return try Output(content)
        } catch {
            throw .invalidOutput("The model's answer didn't match the expected format.")
        }
    }
}
