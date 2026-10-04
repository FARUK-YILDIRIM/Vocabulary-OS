import Foundation
import Synchronization
@testable import VocabularyAI

/// Answers HTTP requests in tests without touching the network. Handlers are registered per host, so
/// tests running in parallel never see each other's responses.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status: Int
        var body: Data
        var headers: [String: String] = ["Content-Type": "application/json"]
        /// Fails the request the way the network would, instead of answering it.
        var failure: URLError.Code?
        /// Redirects the request to this URL.
        var redirect: URL?

        static func failing(_ code: URLError.Code) -> Response {
            Response(status: 0, body: Data(), failure: code)
        }

        static func redirect(to url: URL) -> Response {
            Response(status: 302, body: Data(), headers: ["Location": url.absoluteString], redirect: url)
        }

        static func json(_ status: Int, _ body: String) -> Response {
            Response(status: status, body: Data(body.utf8))
        }

        static func text(_ status: Int, _ body: String) -> Response {
            Response(status: status, body: Data(body.utf8), headers: ["Content-Type": "text/plain"])
        }
    }

    /// A request as the server would see it, with the body read from the stream.
    struct Recorded: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data
        let timeout: TimeInterval

        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        }
    }

    private static let handlers = Mutex<[String: @Sendable (Recorded) -> Response]>([:])
    private static let recorded = Mutex<[String: [Recorded]]>([:])

    /// Returns a session whose requests to `host` are answered by `handler`.
    static func session(host: String, handler: @escaping @Sendable (Recorded) -> Response) -> URLSession {
        handlers.withLock { $0[host] = handler }
        return ProviderHTTP.makeSession(configuration: configuration)
    }

    /// Answers requests to `host` too, for a test that uses another host's session.
    static func answer(host: String, handler: @escaping @Sendable (Recorded) -> Response) {
        handlers.withLock { $0[host] = handler }
    }

    private static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    static func requests(to host: String) -> [Recorded] {
        recorded.withLock { $0[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let recordedRequest = Recorded(
            method: request.httpMethod ?? "GET",
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request),
            timeout: request.timeoutInterval
        )
        Self.recorded.withLock { $0[host, default: []].append(recordedRequest) }
        guard let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = handler(recordedRequest)
        if let failure = response.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)
        if let redirect = response.redirect, let http {
            var next = request
            next.url = redirect
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: http)
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if let http {
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
