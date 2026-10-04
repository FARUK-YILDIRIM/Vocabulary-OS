import Foundation
import VocabularyCore

/// Which wire protocol a provider speaks (ADR-003).
public enum ProviderKind: String, Sendable, Hashable {
    case appleOnDevice
    case openAICompatible
    case anthropic
}

/// How a provider is asked for JSON that follows a schema.
public enum StructuredOutputMode: Sendable, Hashable {
    /// Guided generation on device.
    case guided
    /// `response_format: {type: "json_schema", …}`.
    case jsonSchema(strict: Bool)
    /// `response_format: {type: "json_object"}`; the schema goes into the prompt.
    case jsonObject
    /// Anthropic `output_config.format`.
    case anthropicOutputFormat
}

/// The request field that caps output length.
public enum TokenLimitField: String, Sendable, Hashable {
    case maxTokens = "max_tokens"
    case maxCompletionTokens = "max_completion_tokens"
}

/// Provider-specific request details that don't fit the common shape.
public struct ProviderQuirks: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// OpenRouter: route only to upstream providers that honor `response_format`.
    public static let openRouterRequireParameters = ProviderQuirks(rawValue: 1 << 0)
    /// OpenRouter: identify the app with `X-OpenRouter-Title`.
    public static let openRouterTitleHeader = ProviderQuirks(rawValue: 1 << 1)
    /// The JSON prompt must contain the word "json" and an example (DeepSeek JSON mode).
    public static let jsonModeNeedsExampleInPrompt = ProviderQuirks(rawValue: 1 << 2)
}

/// A model we recommend for a provider. The learner can also pick any model the provider lists.
public struct ModelDescriptor: Identifiable, Sendable, Hashable {
    public let id: String
    public let acceptsImages: Bool

    public init(id: String, acceptsImages: Bool) {
        self.id = id
        self.acceptsImages = acceptsImages
    }
}

/// One entry of the provider list we ship (SPEC C2, ADR-003).
public struct ProviderDescriptor: Identifiable, Sendable, Hashable {
    public let id: String
    public let displayName: String
    public let kind: ProviderKind
    /// `nil` for the on-device model and for the custom endpoint, whose URL the learner enters.
    public let baseURL: URL?
    public let requiresAPIKey: Bool
    /// Where the learner creates a key.
    public let apiKeyPageURL: URL?
    public let structuredOutput: StructuredOutputMode
    public let tokenLimitField: TokenLimitField
    public let quirks: ProviderQuirks
    public let recommendedModels: [ModelDescriptor]
    /// Whether `GET …/models` lists the models available to a key.
    public let supportsModelListing: Bool

    /// Strategy for meaning-in-context: the small on-device model needs focused steps (ADR-003).
    public var insightStrategy: InsightStrategy {
        kind == .appleOnDevice ? .stepwise : .singleCall
    }
}

/// The providers and models we ship. Model IDs change often; review this list every release.
///
/// Last verified against each provider's documentation on 2026-10-04 (sources in ADR-003).
public enum ProviderCatalog {
    public static let customID = "custom"

    public static let onDevice = ProviderDescriptor(
        id: AIProviderSelection.onDevice.providerID,
        displayName: String(localized: "Apple Intelligence (on device)", bundle: .module),
        kind: .appleOnDevice,
        baseURL: nil,
        requiresAPIKey: false,
        apiKeyPageURL: nil,
        structuredOutput: .guided,
        tokenLimitField: .maxTokens,
        quirks: [],
        recommendedModels: [ModelDescriptor(id: "system", acceptsImages: false)],
        supportsModelListing: false
    )

    public static let custom = ProviderDescriptor(
        id: customID,
        displayName: String(localized: "Custom (OpenAI-compatible)", bundle: .module),
        kind: .openAICompatible,
        baseURL: nil,
        requiresAPIKey: false,
        apiKeyPageURL: nil,
        structuredOutput: .jsonSchema(strict: false),
        tokenLimitField: .maxTokens,
        quirks: [],
        recommendedModels: [],
        supportsModelListing: true
    )

    /// Ollama's default address; LM Studio uses http://localhost:1234/v1.
    public static let suggestedCustomBaseURL = url("http://localhost:11434/v1")

    public static let all: [ProviderDescriptor] = [
        onDevice,
        ProviderDescriptor(
            id: "openai",
            displayName: "OpenAI",
            kind: .openAICompatible,
            baseURL: url("https://api.openai.com/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://platform.openai.com/api-keys"),
            structuredOutput: .jsonSchema(strict: true),
            tokenLimitField: .maxCompletionTokens,
            quirks: [],
            recommendedModels: [
                ModelDescriptor(id: "gpt-6-luna", acceptsImages: true),
                ModelDescriptor(id: "gpt-5.4-nano", acceptsImages: true),
                ModelDescriptor(id: "gpt-5.4-mini", acceptsImages: true),
            ],
            supportsModelListing: true
        ),
        ProviderDescriptor(
            id: "anthropic",
            displayName: "Anthropic Claude",
            kind: .anthropic,
            baseURL: url("https://api.anthropic.com/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://platform.claude.com/settings/keys"),
            structuredOutput: .anthropicOutputFormat,
            tokenLimitField: .maxTokens,
            quirks: [],
            recommendedModels: [
                ModelDescriptor(id: "claude-haiku-4-5", acceptsImages: true),
                ModelDescriptor(id: "claude-sonnet-5-5", acceptsImages: true),
            ],
            supportsModelListing: true
        ),
        ProviderDescriptor(
            id: "gemini",
            displayName: "Google Gemini",
            kind: .openAICompatible,
            baseURL: url("https://generativelanguage.googleapis.com/v1beta/openai"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://aistudio.google.com/apikey"),
            structuredOutput: .jsonSchema(strict: false),
            tokenLimitField: .maxTokens,
            quirks: [],
            recommendedModels: [
                ModelDescriptor(id: "gemini-3.1-flash-lite", acceptsImages: true),
                ModelDescriptor(id: "gemini-3.5-flash-lite", acceptsImages: true),
                ModelDescriptor(id: "gemini-3.8-flash", acceptsImages: true),
            ],
            supportsModelListing: true
        ),
        ProviderDescriptor(
            id: "deepseek",
            displayName: "DeepSeek",
            kind: .openAICompatible,
            baseURL: url("https://api.deepseek.com"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://platform.deepseek.com/api_keys"),
            structuredOutput: .jsonObject,
            tokenLimitField: .maxTokens,
            quirks: [.jsonModeNeedsExampleInPrompt],
            recommendedModels: [
                ModelDescriptor(id: "deepseek-flash", acceptsImages: true),
                ModelDescriptor(id: "deepseek-v4-pro", acceptsImages: false),
            ],
            supportsModelListing: true
        ),
        ProviderDescriptor(
            id: "openrouter",
            displayName: "OpenRouter",
            kind: .openAICompatible,
            baseURL: url("https://openrouter.ai/api/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://openrouter.ai/settings/keys"),
            structuredOutput: .jsonSchema(strict: true),
            tokenLimitField: .maxTokens,
            quirks: [.openRouterRequireParameters, .openRouterTitleHeader],
            recommendedModels: [
                ModelDescriptor(id: "google/gemini-3.1-flash-lite", acceptsImages: true),
                ModelDescriptor(id: "openai/gpt-6-luna", acceptsImages: true),
                ModelDescriptor(id: "deepseek/deepseek-v4.1-flash", acceptsImages: true),
                ModelDescriptor(id: "mistralai/mistral-small-2603", acceptsImages: true),
            ],
            supportsModelListing: true
        ),
        ProviderDescriptor(
            id: "mistral",
            displayName: "Mistral",
            kind: .openAICompatible,
            baseURL: url("https://api.mistral.ai/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://console.mistral.ai/api-keys"),
            structuredOutput: .jsonSchema(strict: true),
            tokenLimitField: .maxTokens,
            quirks: [],
            recommendedModels: [
                ModelDescriptor(id: "mistral-small-latest", acceptsImages: false),
                ModelDescriptor(id: "ministral-8b-latest", acceptsImages: true),
            ],
            supportsModelListing: true
        ),
        custom,
    ]

    public static func provider(id: String) -> ProviderDescriptor? {
        all.first { $0.id == id }
    }

    /// Compile-time constants; a typo here is a programming error caught by the catalog tests.
    private static func url(_ string: StaticString) -> URL {
        guard let url = URL(string: "\(string)") else {
            preconditionFailure("Invalid catalog URL \(string)")
        }
        return url
    }
}
