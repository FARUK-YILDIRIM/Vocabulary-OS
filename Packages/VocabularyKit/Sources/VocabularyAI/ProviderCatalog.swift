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
    /// `response_format: {type: "json_object", schema: …}`, Cohere's form of a schema.
    case jsonObjectWithSchema
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
    /// The schema can't bound array lengths (`minItems`, `maxItems`); validators check counts instead.
    public static let dropsArrayBounds = ProviderQuirks(rawValue: 1 << 3)
    /// Qwen models think by default, which eats the output budget: `enable_thinking: false`.
    public static let turnsOffQwenThinking = ProviderQuirks(rawValue: 1 << 4)
    /// The models think by default: `thinking: {type: "disabled"}` (Z.ai).
    public static let turnsOffThinking = ProviderQuirks(rawValue: 1 << 5)
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
    /// `nil` sends no limit: learners' own servers disagree on the field, and Qwen asks for none
    /// with JSON output.
    public let tokenLimitField: TokenLimitField?
    public let quirks: ProviderQuirks
    public let recommendedModels: [ModelDescriptor]
    /// Whether `GET …/models` lists the models available to a key.
    public let supportsModelListing: Bool

    /// Strategy for meaning-in-context: the small on-device model needs focused steps (ADR-003).
    public var insightStrategy: InsightStrategy {
        kind == .appleOnDevice ? .stepwise : .singleCall
    }
}

extension ProviderDescriptor {
    /// A provider the learner added: an OpenAI-compatible server at their address, with an optional
    /// key (SPEC C2). The schema isn't strict and no output limit is sent, since such servers differ
    /// in what they accept.
    public init(custom provider: CustomProvider) {
        self.init(
            id: provider.id,
            displayName: provider.name,
            kind: .openAICompatible,
            baseURL: provider.url,
            requiresAPIKey: false,
            apiKeyPageURL: nil,
            structuredOutput: .jsonSchema(strict: false),
            tokenLimitField: nil,
            quirks: [],
            recommendedModels: [],
            supportsModelListing: true
        )
    }
}

/// The providers and models we ship. Model IDs change often; review this list every release.
///
/// Last verified against each provider's documentation on 2026-10-04 (sources in ADR-003). Learners
/// add other OpenAI-compatible services themselves (`CustomProvider`).
public enum ProviderCatalog {

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

    /// Ollama's default address, shown as an example; LM Studio uses http://localhost:1234/v1.
    public static let exampleCustomAddress = "http://localhost:11434/v1"

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
            id: "xai",
            displayName: "xAI Grok",
            kind: .openAICompatible,
            baseURL: url("https://api.x.ai/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://console.x.ai/team/default/api-keys"),
            structuredOutput: .jsonSchema(strict: true),
            tokenLimitField: .maxCompletionTokens,
            quirks: [],
            recommendedModels: [
                ModelDescriptor(id: "grok-4.3", acceptsImages: true),
                ModelDescriptor(id: "grok-4.20-0309-non-reasoning", acceptsImages: true),
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
        ProviderDescriptor(
            id: "qwen",
            displayName: "Alibaba Qwen",
            kind: .openAICompatible,
            // The shared international address; keys work only in the region they were made in.
            baseURL: url("https://dashscope-intl.aliyuncs.com/compatible-mode/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://modelstudio.console.alibabacloud.com/ap-southeast-1/settings/api-key"),
            // JSON Schema output isn't offered in this region yet.
            structuredOutput: .jsonObject,
            tokenLimitField: nil,
            quirks: [.jsonModeNeedsExampleInPrompt, .turnsOffQwenThinking],
            recommendedModels: [
                ModelDescriptor(id: "qwen3.8-flash", acceptsImages: true),
                ModelDescriptor(id: "qwen3.7-flash", acceptsImages: true),
                ModelDescriptor(id: "qwen-flash", acceptsImages: false),
            ],
            supportsModelListing: false
        ),
        ProviderDescriptor(
            id: "kimi",
            displayName: "Moonshot Kimi",
            kind: .openAICompatible,
            baseURL: url("https://api.moonshot.ai/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://platform.kimi.ai/console/api-keys"),
            structuredOutput: .jsonSchema(strict: true),
            tokenLimitField: .maxCompletionTokens,
            quirks: [.dropsArrayBounds],
            recommendedModels: [
                ModelDescriptor(id: "kimi-k2.6", acceptsImages: true),
                ModelDescriptor(id: "kimi-k3", acceptsImages: true),
            ],
            supportsModelListing: true
        ),
        ProviderDescriptor(
            id: "zai",
            displayName: "Z.ai GLM",
            kind: .openAICompatible,
            baseURL: url("https://api.z.ai/api/paas/v4"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://z.ai/manage-apikey/apikey-list"),
            structuredOutput: .jsonObject,
            tokenLimitField: .maxTokens,
            quirks: [.jsonModeNeedsExampleInPrompt, .turnsOffThinking],
            recommendedModels: [
                ModelDescriptor(id: "glm-4.7-flashx", acceptsImages: false),
                ModelDescriptor(id: "glm-4.7-flash", acceptsImages: false),
            ],
            supportsModelListing: false
        ),
        ProviderDescriptor(
            id: "cohere",
            displayName: "Cohere",
            kind: .openAICompatible,
            baseURL: url("https://api.cohere.ai/compatibility/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://dashboard.cohere.com/api-keys"),
            structuredOutput: .jsonObjectWithSchema,
            tokenLimitField: .maxTokens,
            quirks: [.dropsArrayBounds],
            recommendedModels: [
                ModelDescriptor(id: "command-r-08-2024", acceptsImages: false),
                ModelDescriptor(id: "command-a-03-2025", acceptsImages: false),
            ],
            supportsModelListing: false
        ),
        ProviderDescriptor(
            id: "groq",
            displayName: "Groq",
            kind: .openAICompatible,
            baseURL: url("https://api.groq.com/openai/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://console.groq.com/keys"),
            structuredOutput: .jsonSchema(strict: true),
            tokenLimitField: .maxCompletionTokens,
            quirks: [.dropsArrayBounds],
            recommendedModels: [
                ModelDescriptor(id: "openai/gpt-oss-120b", acceptsImages: false),
                ModelDescriptor(id: "openai/gpt-oss-20b", acceptsImages: false),
                ModelDescriptor(id: "qwen/qwen3.8-27b", acceptsImages: true),
            ],
            supportsModelListing: true
        ),
        ProviderDescriptor(
            id: "cerebras",
            displayName: "Cerebras",
            kind: .openAICompatible,
            baseURL: url("https://api.cerebras.ai/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://cloud.cerebras.ai"),
            structuredOutput: .jsonSchema(strict: true),
            tokenLimitField: .maxCompletionTokens,
            quirks: [.dropsArrayBounds],
            recommendedModels: [
                ModelDescriptor(id: "gpt-oss-120b", acceptsImages: false),
                ModelDescriptor(id: "qwen-3.8-27b", acceptsImages: true),
            ],
            supportsModelListing: true
        ),
        ProviderDescriptor(
            id: "together",
            displayName: "Together AI",
            kind: .openAICompatible,
            baseURL: url("https://api.together.ai/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://api.together.ai/settings/projects/~current/api-keys"),
            structuredOutput: .jsonSchema(strict: false),
            tokenLimitField: .maxTokens,
            quirks: [.dropsArrayBounds],
            recommendedModels: [
                ModelDescriptor(id: "openai/gpt-oss-120b", acceptsImages: false),
                ModelDescriptor(id: "Qwen/Qwen3.5-9B", acceptsImages: true),
                ModelDescriptor(id: "deepseek-ai/DeepSeek-V4.1-Flash", acceptsImages: false),
            ],
            supportsModelListing: true
        ),
        ProviderDescriptor(
            id: "fireworks",
            displayName: "Fireworks AI",
            kind: .openAICompatible,
            baseURL: url("https://api.fireworks.ai/inference/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://app.fireworks.ai/settings/users/api-keys"),
            structuredOutput: .jsonSchema(strict: false),
            tokenLimitField: .maxTokens,
            quirks: [],
            recommendedModels: [
                ModelDescriptor(id: "accounts/fireworks/models/glm-5p3-flash", acceptsImages: true),
                ModelDescriptor(id: "accounts/fireworks/models/deepseek-v4p1-flash", acceptsImages: true),
                ModelDescriptor(id: "accounts/fireworks/models/gpt-oss-120b", acceptsImages: false),
            ],
            supportsModelListing: false
        ),
        ProviderDescriptor(
            id: "huggingface",
            displayName: "Hugging Face",
            kind: .openAICompatible,
            baseURL: url("https://router.huggingface.co/v1"),
            requiresAPIKey: true,
            apiKeyPageURL: url("https://huggingface.co/settings/tokens/new?ownUserPermissions=inference.serverless.write&tokenType=fineGrained"),
            structuredOutput: .jsonSchema(strict: false),
            tokenLimitField: .maxTokens,
            quirks: [.dropsArrayBounds],
            // A ":provider" suffix picks a host that enforces the schema.
            recommendedModels: [
                ModelDescriptor(id: "openai/gpt-oss-120b", acceptsImages: false),
                ModelDescriptor(id: "zai-org/GLM-5.3-Flash:baseten", acceptsImages: true),
                ModelDescriptor(id: "deepseek-ai/DeepSeek-V4.1-Flash:baseten", acceptsImages: true),
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
