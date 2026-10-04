import Darwin
import Foundation

/// An AI provider the learner added: any service with an OpenAI-compatible API, such as Ollama or
/// LM Studio on a Mac, or a company's gateway (SPEC C2, ADR-003). Its key, if it needs one, is kept
/// in the Keychain under its `id`, like the keys of the providers we list.
public struct CustomProvider: Codable, Hashable, Sendable, Identifiable {
    public static let idPrefix = "custom-"

    public var id: String
    public var name: String
    /// The API's base address, the part before `/chat/completions`.
    public var address: String

    public init(id: String = CustomProvider.idPrefix + UUID().uuidString.lowercased(), name: String, address: String) {
        self.id = id
        self.name = name
        self.address = address
    }

    /// Whether a provider ID belongs to a provider the learner added.
    public static func isCustom(_ providerID: String) -> Bool {
        providerID.hasPrefix(idPrefix)
    }

    /// The address, if it is one the app may use (`ServerAddress.validate`).
    public var url: URL? {
        try? ServerAddress.validate(address).get()
    }

    /// Whether the server runs on this device (`localhost`). Other devices can't reach it at this
    /// address, so choosing it doesn't change their choice (SPEC C2).
    public var isOnThisDevice: Bool {
        url.map(ServerAddress.isLoopback) ?? false
    }

    /// Whether editing `old` into `new` points the provider at another server. A key only ever goes
    /// to the server it was entered for, so the key saved for `old` must then be removed (SPEC C2).
    public static func movesToAnotherServer(from old: CustomProvider, to new: CustomProvider) -> Bool {
        guard let oldURL = old.url, let newURL = new.url else { return true }
        return !ServerAddress.isSameServer(oldURL, newURL)
    }
}

/// Checks the server addresses learners type for their own providers (SPEC C2).
public enum ServerAddress {
    public enum Problem: Error, Equatable, Sendable {
        /// Not a full `http` or `https` address with a host.
        case notAnAddress
        /// Plain `http` to a server on the internet, where the key and the learner's words would
        /// travel unencrypted. App Transport Security allows `http` on the local network only.
        case plainHTTPOnInternet
    }

    /// The address as a URL if the app may use it: `https` anywhere, plain `http` only on this device
    /// or the local network.
    public static func validate(_ text: String) -> Result<URL, Problem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", host(of: url)?.isEmpty == false
        else {
            return .failure(.notAnAddress)
        }
        if scheme == "http" && !isLocalNetwork(url) {
            return .failure(.plainHTTPOnInternet)
        }
        return .success(url)
    }

    /// Whether the address is this device itself: `localhost`, 127.0.0.0/8 or `::1`.
    public static func isLoopback(_ url: URL) -> Bool {
        guard let host = host(of: url) else { return false }
        if host == "localhost" { return true }
        if let bytes = ipv4(host) { return bytes[0] == 127 }
        if let bytes = ipv6(host) { return bytes == [UInt8](repeating: 0, count: 15) + [1] }
        return false
    }

    /// Whether the address is on this device or the local network: private and link-local IP
    /// addresses, `.local` names and names without a dot, as App Transport Security counts them.
    public static func isLocalNetwork(_ url: URL) -> Bool {
        guard let host = host(of: url) else { return false }
        if isLoopback(url) { return true }
        if let bytes = ipv4(host) {
            return bytes[0] == 10
                || (bytes[0] == 172 && (16...31).contains(bytes[1]))
                || (bytes[0] == 192 && bytes[1] == 168)
                || (bytes[0] == 169 && bytes[1] == 254)
        }
        if let bytes = ipv6(host) {
            // Link-local fe80::/10 and unique local fc00::/7.
            return (bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80) || bytes[0] & 0xFE == 0xFC
        }
        return host.hasSuffix(".local") || !host.contains(".")
    }

    /// Whether two addresses reach the same server: the same scheme, host and port.
    public static func isSameServer(_ first: URL, _ second: URL) -> Bool {
        first.scheme?.lowercased() == second.scheme?.lowercased()
            && host(of: first) == host(of: second)
            && port(of: first) == port(of: second)
    }

    /// The lowercased host, without the brackets of an IPv6 address.
    private static func host(of url: URL) -> String? {
        url.host(percentEncoded: false)?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
    }

    private static func port(of url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : url.scheme?.lowercased() == "http" ? 80 : nil)
    }

    private static func ipv4(_ host: String) -> [UInt8]? {
        var address = in_addr()
        guard inet_pton(AF_INET, host, &address) == 1 else { return nil }
        return withUnsafeBytes(of: address) { Array($0) }
    }

    private static func ipv6(_ host: String) -> [UInt8]? {
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else { return nil }
        return withUnsafeBytes(of: address) { Array($0) }
    }
}
