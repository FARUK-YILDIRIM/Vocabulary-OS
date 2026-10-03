import Foundation
import FoundationModels
import Testing
@testable import VocabularyAI

@Generable
struct ProbeOutput {
    @Guide(description: "A word")
    var word: String
    @Guide(description: "Two items", .count(2))
    var items: [String]
}

@Suite struct OpenAICompatibleClientTests {
    private let request = GenerationRequest(instructions: "You are a dictionary.", prompt: "Term: «cookie»", maximumResponseTokens: 300)

    private func client(
        _ providerID: String,
        apiKey: String? = "sk-test",
        status: Int = 200,
        body: String = #"{"choices":[{"message":{"content":"{\"word\":\"çerez\",\"items\":[\"a\",\"b\"]}"},"finish_reason":"stop"}]}"#
    ) throws -> (OpenAICompatibleClient, String) {
        let host = "\(providerID)-\(UUID().uuidString.lowercased()).test"
        let session = StubURLProtocol.session(host: host) { _ in .json(status, body) }
        let provider = try #require(ProviderCatalog.provider(id: providerID))
        let baseURL = try #require(URL(string: "https://\(host)/v1"))
        return (OpenAICompatibleClient(provider: provider, baseURL: baseURL, model: "test-model", apiKey: apiKey, session: session), host)
    }

    @Test func sendsAStrictJSONSchemaRequestToOpenAI() async throws {
        let (client, host) = try client("openai")
        let output = try await client.generate(request, as: ProbeOutput.self)
        #expect(output.word == "çerez")

        let sent = try #require(StubURLProtocol.requests(to: host).first)
        #expect(sent.method == "POST")
        #expect(sent.url.path() == "/v1/chat/completions")
        #expect(sent.headers["Authorization"] == "Bearer sk-test")
        let body = sent.json
        #expect(body["model"] as? String == "test-model")
        #expect(body["max_completion_tokens"] as? Int == 2048)
        #expect(body["max_tokens"] == nil)
        #expect(body["temperature"] == nil, "reasoning models reject custom temperatures")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let jsonSchema = try #require(format["json_schema"] as? [String: Any])
        #expect(jsonSchema["strict"] as? Bool == true)
        let schema = try #require(jsonSchema["schema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(schema["x-order"] == nil && schema["title"] == nil)
    }

    @Test func usesJSONModeWithTheSchemaInThePromptForDeepSeek() async throws {
        let (client, host) = try client("deepseek")
        _ = try await client.generate(request, as: ProbeOutput.self)

        let body = try #require(StubURLProtocol.requests(to: host).first).json
        #expect((body["response_format"] as? [String: Any])?["type"] as? String == "json_object")
        #expect(body["max_tokens"] as? Int == 2048)
        let messages = try #require(body["messages"] as? [[String: Any]])
        let system = try #require(messages.first?["content"] as? String)
        #expect(system.contains("JSON"))
        #expect(system.contains("\"word\""), "the schema and an example go into the prompt")
    }

    @Test func asksOpenRouterForProvidersThatHonorTheSchema() async throws {
        let (client, host) = try client("openrouter")
        _ = try await client.generate(request, as: ProbeOutput.self)

        let sent = try #require(StubURLProtocol.requests(to: host).first)
        #expect(sent.headers["X-OpenRouter-Title"] == "Vocabulary-OS")
        #expect((sent.json["provider"] as? [String: Any])?["require_parameters"] as? Bool == true)
    }

    @Test func omitsAuthorizationForKeylessLocalServers() async throws {
        let (client, host) = try client("custom", apiKey: nil)
        _ = try await client.generate(request, as: ProbeOutput.self)
        #expect(try #require(StubURLProtocol.requests(to: host).first).headers["Authorization"] == nil)
    }

    @Test func readsJSONWrappedInCodeFences() async throws {
        let fenced = #"{"choices":[{"message":{"content":"Here you go:\n```json\n{\"word\":\"kurabiye\",\"items\":[\"a\",\"b\"]}\n```"}}]}"#
        let (client, _) = try client("mistral", body: fenced)
        #expect(try await client.generate(request, as: ProbeOutput.self).word == "kurabiye")
    }

    @Test func rejectsUnreadableAnswers() async throws {
        let (client, _) = try client("openai", body: #"{"choices":[{"message":{"content":"Sorry, I can't."}}]}"#)
        await #expect(throws: AIError.self) {
            try await client.generate(request, as: ProbeOutput.self)
        }
    }

    @Test func reportsRefusals() async throws {
        let (client, _) = try client("openai", body: #"{"choices":[{"message":{"content":null,"refusal":"I can't help with that."}}]}"#)
        await #expect(throws: AIError.refusal) {
            try await client.generate(request, as: ProbeOutput.self)
        }
    }

    @Test(arguments: [
        (401, #"{"error":{"message":"Incorrect API key","type":"invalid_request_error"}}"#, AIError.invalidAPIKey),
        (402, #"{"error":{"message":"Insufficient credits","code":402}}"#, AIError.quotaExceeded),
        (429, #"{"error":{"message":"You exceeded your quota","type":"insufficient_quota"}}"#, AIError.quotaExceeded),
        (429, #"{"error":{"message":"Rate limit reached","type":"rate_limit_error"}}"#, AIError.rateLimited),
        (400, #"[{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}]"#, AIError.invalidAPIKey),
        (404, #"{"error":{"message":"The model does not exist"}}"#, AIError.modelUnavailable),
        (503, #"{"error":{"message":"overloaded"}}"#, AIError.server(status: 503)),
    ])
    func mapsHTTPErrors(status: Int, body: String, expected: AIError) async throws {
        let (client, _) = try client("openai", status: status, body: body)
        await #expect(throws: expected) {
            try await client.generate(request, as: ProbeOutput.self)
        }
    }

    @Test func understandsPlainTextErrors() async throws {
        let host = "deepseek-plain-\(UUID().uuidString.lowercased()).test"
        let session = StubURLProtocol.session(host: host) { _ in .text(401, "Authentication Fails (no such user)") }
        let client = OpenAICompatibleClient(
            provider: try #require(ProviderCatalog.provider(id: "deepseek")),
            baseURL: try #require(URL(string: "https://\(host)")), model: "deepseek-flash", apiKey: "bad", session: session
        )
        await #expect(throws: AIError.invalidAPIKey) {
            try await client.generate(request, as: ProbeOutput.self)
        }
    }

    @Test func listsTheModelsAvailableToTheKey() async throws {
        let host = "models-\(UUID().uuidString.lowercased()).test"
        let session = StubURLProtocol.session(host: host) { _ in
            .json(200, #"{"object":"list","data":[{"id":"gpt-6-luna"},{"id":"gpt-5.4-nano"}]}"#)
        }
        let client = OpenAICompatibleClient(
            provider: try #require(ProviderCatalog.provider(id: "openai")),
            baseURL: try #require(URL(string: "https://\(host)/v1")), model: "gpt-6-luna", apiKey: "sk", session: session
        )
        #expect(try await client.listModels() == ["gpt-5.4-nano", "gpt-6-luna"])
        #expect(StubURLProtocol.requests(to: host).first?.url.path() == "/v1/models")
    }
}

@Suite struct JSONSchemaAdapterTests {
    @Test func removesKeysProvidersRejectAndKeepsTheConstraints() throws {
        let schema = try JSONSchemaAdapter.jsonObject(for: ProbeOutput.generationSchema, dropArrayBounds: false)
        #expect(schema["title"] == nil && schema["x-order"] == nil)
        #expect(schema["required"] as? [String] == ["word", "items"])
        let items = try #require((schema["properties"] as? [String: Any])?["items"] as? [String: Any])
        #expect(items["minItems"] as? Int == 2)
    }

    @Test func canDropArrayBoundsForProvidersThatDontSupportThem() throws {
        let schema = try JSONSchemaAdapter.jsonObject(for: ProbeOutput.generationSchema, dropArrayBounds: true)
        let items = try #require((schema["properties"] as? [String: Any])?["items"] as? [String: Any])
        #expect(items["minItems"] == nil && items["maxItems"] == nil)
    }

    @Test func theCloudInsightSchemaIsValidForStrictModes() throws {
        let spec = try InsightPrompts.fullEntry(InsightRequest(term: "Bank", sentence: "Wir saßen auf einer Bank.", language: .german, nativeLanguage: .turkish))
        let schema = try JSONSchemaAdapter.jsonObject(for: spec.schema, dropArrayBounds: false)
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(Set(schema["required"] as? [String] ?? []) == Set(properties.keys))
        let examples = try #require(properties["examples"] as? [String: Any])
        let example = try #require(examples["items"] as? [String: Any])
        #expect(example["additionalProperties"] as? Bool == false)
        #expect(Set(example["required"] as? [String] ?? []) == ["sentence", "translation"])
        #expect(schema["$defs"] == nil, "sub-schemas are inlined")
        let partOfSpeech = try #require(properties["partOfSpeech"] as? [String: Any])
        #expect(partOfSpeech["type"] as? String == "string")
        #expect((partOfSpeech["enum"] as? [String])?.contains("noun") == true)
    }

    @Test(arguments: [
        ("{\"a\":1}", "{\"a\":1}"),
        ("```json\n{\"a\":1}\n```", "{\"a\":1}"),
        ("Sure! {\"a\":{\"b\":2}} Done.", "{\"a\":{\"b\":2}}"),
    ])
    func extractsTheJSONObjectFromText(_ text: String, _ expected: String) {
        #expect(JSONSchemaAdapter.extractJSONObject(from: text) == expected)
    }
}
