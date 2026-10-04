import Foundation
import FoundationModels

/// Anthropic Messages API client (ADR-003).
///
/// Structured output uses `output_config.format`, which is generally available. Forced tool use
/// (`tool_choice`) returns 400 on the newest Claude models, so it is not used.
public struct AnthropicClient: GenerationClient {
    public static let apiVersion = "2023-06-01"

    public let baseURL: URL
    public let model: String
    private let apiKey: String
    private let session: URLSession

    public init(baseURL: URL, model: String, apiKey: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        // Provider requests keep nothing on disk and follow no redirect to another server.
        self.session = session ?? ProviderHTTP.session
    }

    public var supportsImages: Bool { true }

    public func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent {
        // Anthropic accepts minItems of only 0 or 1; validators enforce counts instead.
        let schemaObject = try JSONSchemaAdapter.jsonObject(for: schema, dropArrayBounds: true)
        let body: [String: Any] = [
            "model": model,
            "max_tokens": max(request.maximumResponseTokens * 4, 2048),
            "system": request.instructions,
            "messages": [["role": "user", "content": userContent(for: request)]],
            "output_config": ["format": ["type": "json_schema", "schema": schemaObject]],
        ]
        var urlRequest = URLRequest(url: baseURL.appending(path: "messages"), timeoutInterval: ProviderHTTP.timeout(for: request))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&urlRequest)
        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw .unknown("The request could not be encoded")
        }
        let data = try await ProviderHTTP.send(urlRequest, session: session)
        return try parseReply(data)
    }

    /// Model IDs available to the key, from `GET /v1/models`.
    public func listModels() async throws(AIError) -> [String] {
        var components = URLComponents(url: baseURL.appending(path: "models"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: "1000")]
        guard let url = components?.url else { throw .unknown("Invalid models URL") }
        var request = URLRequest(url: url, timeoutInterval: ProviderHTTP.timeout)
        authorize(&request)
        let data = try await ProviderHTTP.send(request, session: session)
        struct List: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else {
            throw .invalidOutput("The model list could not be read.")
        }
        return list.data.map(\.id).sorted()
    }

    /// The prompt, after the photo when there is one, as Anthropic recommends.
    private func userContent(for request: GenerationRequest) -> Any {
        guard let image = request.image else { return request.prompt }
        return [
            ["type": "image", "source": ["type": "base64", "media_type": image.mediaType, "data": image.jpegData.base64EncodedString()]],
            ["type": "text", "text": request.prompt],
        ]
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
    }

    private func parseReply(_ data: Data) throws(AIError) -> GeneratedContent {
        struct Reply: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let content: [Block]
            let stopReason: String?

            enum CodingKeys: String, CodingKey {
                case content
                case stopReason = "stop_reason"
            }
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw .invalidOutput("The provider's reply could not be read.")
        }
        switch reply.stopReason {
        case "refusal":
            throw .refusal
        case "max_tokens":
            throw .invalidOutput("The answer was cut off at the output limit.")
        default:
            break
        }
        // Thinking blocks can come first; only text blocks carry the answer.
        let text = reply.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        return try JSONSchemaAdapter.content(fromReply: text)
    }
}
