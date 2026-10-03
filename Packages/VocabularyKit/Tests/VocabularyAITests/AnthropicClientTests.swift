import Foundation
import Testing
@testable import VocabularyAI

@Suite struct AnthropicClientTests {
    private let request = GenerationRequest(instructions: "You are a dictionary.", prompt: "Term: «Bank»", maximumResponseTokens: 300)

    private func client(status: Int = 200, body: String) throws -> (AnthropicClient, String) {
        let host = "anthropic-\(UUID().uuidString.lowercased()).test"
        let session = StubURLProtocol.session(host: host) { _ in .json(status, body) }
        let baseURL = try #require(URL(string: "https://\(host)/v1"))
        return (AnthropicClient(baseURL: baseURL, model: "claude-haiku-4-5", apiKey: "sk-ant-test", session: session), host)
    }

    private let answer = #"{"content":[{"type":"thinking","thinking":"…"},{"type":"text","text":"{\"word\":\"bank\",\"items\":[\"a\",\"b\"]}"}],"stop_reason":"end_turn"}"#

    @Test func sendsTheSchemaThroughOutputConfig() async throws {
        let (client, host) = try client(body: answer)
        let output = try await client.generate(request, as: ProbeOutput.self)
        #expect(output.word == "bank")

        let sent = try #require(StubURLProtocol.requests(to: host).first)
        #expect(sent.url.path() == "/v1/messages")
        #expect(sent.headers["x-api-key"] == "sk-ant-test")
        #expect(sent.headers["anthropic-version"] == "2023-06-01")
        #expect(sent.headers["Authorization"] == nil)
        let body = sent.json
        #expect(body["model"] as? String == "claude-haiku-4-5")
        #expect(body["max_tokens"] as? Int == 2048)
        #expect(body["system"] as? String == "You are a dictionary.")
        #expect(body["tool_choice"] == nil, "forced tool use fails on the newest models")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "user")
        let format = try #require((body["output_config"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
        let items = try #require((schema["properties"] as? [String: Any])?["items"] as? [String: Any])
        #expect(items["minItems"] == nil, "Anthropic only accepts minItems 0 or 1")
    }

    @Test func reportsRefusals() async throws {
        let (client, _) = try client(body: #"{"content":[{"type":"text","text":""}],"stop_reason":"refusal"}"#)
        await #expect(throws: AIError.refusal) {
            try await client.generate(request, as: ProbeOutput.self)
        }
    }

    @Test func reportsAnswersCutOffAtTheLimit() async throws {
        let (client, _) = try client(body: #"{"content":[{"type":"text","text":"{\"word\":\"ba"}],"stop_reason":"max_tokens"}"#)
        await #expect(throws: AIError.invalidOutput("The answer was cut off at the output limit.")) {
            try await client.generate(request, as: ProbeOutput.self)
        }
    }

    @Test(arguments: [
        (401, #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#, AIError.invalidAPIKey),
        (402, #"{"type":"error","error":{"type":"billing_error","message":"Your credit balance is too low"}}"#, AIError.quotaExceeded),
        (429, #"{"type":"error","error":{"type":"rate_limit_error","message":"Number of requests has exceeded your rate limit"}}"#, AIError.rateLimited),
        (429, #"{"type":"error","error":{"type":"rate_limit_error","message":"Monthly limit","details":{"error_code":"enforced_spend_limit_reached"}}}"#, AIError.quotaExceeded),
        (529, #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#, AIError.server(status: 529)),
    ])
    func mapsErrors(status: Int, body: String, expected: AIError) async throws {
        let (client, _) = try client(status: status, body: body)
        await #expect(throws: expected) {
            try await client.generate(request, as: ProbeOutput.self)
        }
    }

    @Test func listsModels() async throws {
        let (client, host) = try client(body: #"{"data":[{"id":"claude-sonnet-5-5","display_name":"Claude Sonnet 5.5"},{"id":"claude-haiku-4-5-20251001"}],"has_more":false}"#)
        #expect(try await client.listModels() == ["claude-haiku-4-5-20251001", "claude-sonnet-5-5"])
        let sent = try #require(StubURLProtocol.requests(to: host).first)
        #expect(sent.url.path() == "/v1/models")
        #expect(sent.headers["x-api-key"] == "sk-ant-test")
    }
}
