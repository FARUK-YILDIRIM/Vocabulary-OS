import Foundation
import FoundationModels

/// Chat Completions client for OpenAI and every provider that speaks the same API: Gemini's
/// OpenAI-compatible endpoint, DeepSeek, OpenRouter, Mistral, and local servers (ADR-003).
public struct OpenAICompatibleClient: GenerationClient {
    public let provider: ProviderDescriptor
    public let baseURL: URL
    public let model: String
    private let apiKey: String?
    private let session: URLSession

    public init(provider: ProviderDescriptor, baseURL: URL, model: String, apiKey: String?, session: URLSession = .shared) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.session = session
    }

    public var supportsImages: Bool { true }

    public func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent {
        let schemaObject = try JSONSchemaAdapter.jsonObject(for: schema, dropArrayBounds: false)
        var system = request.instructions + "\n\nReply with JSON only."
        var body: [String: Any] = ["model": model]
        switch provider.structuredOutput {
        case .jsonSchema(let strict):
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": "vocabulary_output", "strict": strict, "schema": schemaObject],
            ]
        case .jsonObject:
            // JSON mode needs the word "json" and an example of the output in the prompt.
            body["response_format"] = ["type": "json_object"]
            system += """

            Reply with a single JSON object that matches this JSON Schema:
            \(JSONSchemaAdapter.jsonString(schemaObject))
            Example of the shape (replace every value):
            \(JSONSchemaAdapter.jsonString(JSONSchemaAdapter.example(for: schemaObject)))
            """
        case .guided, .anthropicOutputFormat:
            throw .unknown("\(provider.id) does not use the Chat Completions API")
        }
        body["messages"] = [
            ["role": "system", "content": system],
            ["role": "user", "content": userContent(for: request)],
        ]
        // Reasoning models count thinking against this limit; it caps cost, not the answer size.
        body[provider.tokenLimitField.rawValue] = max(request.maximumResponseTokens * 4, 2048)
        // No temperature: reasoning models reject anything but their default.
        if provider.quirks.contains(.openRouterRequireParameters) {
            body["provider"] = ["require_parameters": true]
        }

        var urlRequest = URLRequest(url: baseURL.appending(path: "chat/completions"), timeoutInterval: ProviderHTTP.timeout)
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

    /// Model IDs available to the key, from `GET …/models`.
    public func listModels() async throws(AIError) -> [String] {
        var request = URLRequest(url: baseURL.appending(path: "models"), timeoutInterval: ProviderHTTP.timeout)
        authorize(&request)
        let data = try await ProviderHTTP.send(request, session: session)
        struct List: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else {
            throw .invalidOutput("The model list could not be read.")
        }
        // Gemini's compatible endpoint prefixes IDs with "models/".
        return list.data.map { $0.id.hasPrefix("models/") ? String($0.id.dropFirst(7)) : $0.id }.sorted()
    }

    /// The prompt, followed by the photo as a data URL when there is one.
    private func userContent(for request: GenerationRequest) -> Any {
        guard let image = request.image else { return request.prompt }
        return [
            ["type": "text", "text": request.prompt],
            ["type": "image_url", "image_url": ["url": "data:\(image.mediaType);base64,\(image.jpegData.base64EncodedString())"]],
        ]
    }

    private func authorize(_ request: inout URLRequest) {
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if provider.quirks.contains(.openRouterTitleHeader) {
            request.setValue("Vocabulary-OS", forHTTPHeaderField: "X-OpenRouter-Title")
        }
    }

    private func parseReply(_ data: Data) throws(AIError) -> GeneratedContent {
        guard let reply = try? JSONDecoder().decode(ChatReply.self, from: data) else {
            // OpenRouter can report errors that happen mid-generation with HTTP 200.
            if (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] != nil {
                throw ProviderHTTP.error(status: 400, body: data)
            }
            throw .invalidOutput("The provider's reply could not be read.")
        }
        guard let choice = reply.choices.first else {
            throw .invalidOutput("The provider returned no answer.")
        }
        if let refusal = choice.message.refusal, !refusal.isEmpty {
            throw .refusal
        }
        let text = choice.message.content ?? ""
        if text.isEmpty && choice.finishReason == "length" {
            throw .invalidOutput("The answer was cut off at the output limit.")
        }
        return try JSONSchemaAdapter.content(fromReply: text)
    }
}

private struct ChatReply: Decodable {
    struct Choice: Decodable {
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        let content: String?
        let refusal: String?

        enum CodingKeys: String, CodingKey {
            case content, refusal
        }

        /// `content` is a string for most providers and an array of text parts for some.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            refusal = try container.decodeIfPresent(String.self, forKey: .refusal)
            if let text = try? container.decodeIfPresent(String.self, forKey: .content) {
                content = text
            } else if let parts = try? container.decodeIfPresent([Part].self, forKey: .content) {
                content = parts.compactMap(\.text).joined()
            } else {
                content = nil
            }
        }
    }

    struct Part: Decodable {
        let text: String?
    }

    let choices: [Choice]
}
