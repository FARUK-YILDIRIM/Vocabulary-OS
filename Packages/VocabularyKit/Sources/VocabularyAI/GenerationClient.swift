import Foundation
import FoundationModels

/// A photo for a model that reads images: a downscaled JPEG without metadata (ADR-005).
public struct GenerationImage: Sendable, Hashable {
    public var jpegData: Data

    public init(jpegData: Data) {
        self.jpegData = jpegData
    }

    public var mediaType: String { "image/jpeg" }
}

/// One generation task: who the model is (instructions), what to do (prompt) and how to sample.
public struct GenerationRequest: Sendable, Hashable {
    public var instructions: String
    public var prompt: String
    /// Greedy decoding gives repeatable answers; use it for lookups, not for creative text.
    public var isGreedy: Bool
    public var temperature: Double?
    /// Always set: on device, the 4,096-token context holds instructions, schema, prompt and output.
    public var maximumResponseTokens: Int
    /// A photo the model looks at along with the prompt; only clients that support images send it.
    public var image: GenerationImage?

    public init(
        instructions: String,
        prompt: String,
        isGreedy: Bool = true,
        temperature: Double? = nil,
        maximumResponseTokens: Int = 500,
        image: GenerationImage? = nil
    ) {
        self.instructions = instructions
        self.prompt = prompt
        self.isGreedy = isGreedy
        self.temperature = temperature
        self.maximumResponseTokens = maximumResponseTokens
        self.image = image
    }
}

/// A model that produces structured output for a schema (ADR-003).
///
/// Outputs are defined once as `@Generable` types. The on-device client uses guided generation with
/// the schema directly; cloud clients send the schema as JSON Schema and parse the reply back into
/// `GeneratedContent`.
public protocol GenerationClient: Sendable {
    /// Whether requests can carry an image. The on-device model reads text only; cloud clients send
    /// the image, though the model behind them may still reject it.
    var supportsImages: Bool { get }

    func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent
}

extension GenerationClient {
    public var supportsImages: Bool { false }

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
