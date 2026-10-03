import Foundation

/// HTTP plumbing shared by the cloud clients: sending, and turning failures into `AIError`.
enum ProviderHTTP {
    static let timeout: TimeInterval = 60

    /// Sends the request and returns the body of a 2xx response.
    static func send(_ request: URLRequest, session: URLSession) async throws(AIError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw .network("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw self.error(status: http.statusCode, body: data)
        }
        return data
    }

    /// Maps a failed response. Providers disagree on error bodies (ADR-003): objects, arrays (Gemini's
    /// OpenAI-compatible endpoint) and plain text (DeepSeek), so the text is searched as a whole.
    static func error(status: Int, body: Data) -> AIError {
        let text = errorText(from: body)
        let lowercased = text.lowercased()
        let mentionsQuota = ["quota", "credit", "billing", "balance", "spend limit", "spend_limit", "insufficient_funds"]
            .contains { lowercased.contains($0) }
        let mentionsInvalidKey = ["api_key_invalid", "api key not valid", "invalid api key", "incorrect api key", "invalid x-api-key"]
            .contains { lowercased.contains($0) }
        switch status {
        case 401:
            return .invalidAPIKey
        case 402:
            return .quotaExceeded
        case 403:
            return lowercased.contains("moderation") || lowercased.contains("flagged") ? .guardrailViolation : .invalidAPIKey
        case 404:
            return .modelUnavailable
        case 408:
            return .network("The request timed out")
        case 429:
            return mentionsQuota ? .quotaExceeded : .rateLimited
        case 400, 422:
            if mentionsInvalidKey { return .invalidAPIKey }
            if mentionsQuota { return .quotaExceeded }
            if lowercased.contains("model") && (lowercased.contains("not found") || lowercased.contains("does not exist")) {
                return .modelUnavailable
            }
            return .unknown("HTTP \(status): \(text.prefix(200))")
        case 500...599:
            return .server(status: status)
        default:
            return .unknown("HTTP \(status)")
        }
    }

    /// Every message, type, code and status string in the body, or the body itself when it isn't JSON.
    static func errorText(from body: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: body) else {
            return String(decoding: body, as: UTF8.self)
        }
        var parts: [String] = []
        func collect(_ value: Any) {
            switch value {
            case let object as [String: Any]:
                for key in ["message", "type", "code", "error_code", "status", "reason", "error", "detail"] {
                    if let string = object[key] as? String { parts.append(string) }
                }
                object.values.forEach(collect)
            case let array as [Any]:
                array.forEach(collect)
            default:
                break
            }
        }
        collect(json)
        return parts.joined(separator: " ")
    }
}
