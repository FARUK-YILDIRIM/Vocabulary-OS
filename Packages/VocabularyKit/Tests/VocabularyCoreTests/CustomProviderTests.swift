import Foundation
import Testing
@testable import VocabularyCore

@Suite struct ServerAddressTests {
    @Test(arguments: [
        "https://api.example.com/v1",
        "https://my-gateway.example.org:8443/openai/v1",
        "http://localhost:11434/v1",
        "http://127.0.0.1:1234/v1",
        "http://[::1]:11434/v1",
        "http://192.168.1.20:11434/v1",
        "http://10.0.0.5/v1",
        "http://172.20.1.1:8080/v1",
        "http://169.254.10.2/v1",
        "http://mac-mini.local:1234/v1",
        "http://studio:1234/v1",
        "http://[fd12:3456::1]:8080/v1",
    ])
    func acceptsHTTPSAndLocalNetworkHTTP(_ address: String) throws {
        let url = try ServerAddress.validate(" \(address)\n").get()
        #expect(url.absoluteString == address)
    }

    @Test(arguments: [
        "http://api.example.com/v1",
        "http://8.8.8.8/v1",
        "http://172.32.0.1/v1",
        "http://192.169.1.1/v1",
        "http://[2001:db8::1]/v1",
    ])
    func refusesPlainHTTPOnTheInternet(_ address: String) {
        #expect(ServerAddress.validate(address) == .failure(.plainHTTPOnInternet))
    }

    @Test(arguments: ["", "localhost:11434/v1", "api.example.com", "ftp://example.com/v1", "https://", "http:///v1"])
    func refusesWhatIsNotAFullAddress(_ address: String) {
        #expect(ServerAddress.validate(address) == .failure(.notAnAddress))
    }

    @Test func onlyTheDeviceItselfIsLoopback() throws {
        for address in ["http://localhost:11434/v1", "http://127.0.0.1/v1", "http://127.4.5.6/v1", "http://[::1]/v1", "http://LOCALHOST/v1"] {
            #expect(ServerAddress.isLoopback(try #require(URL(string: address))), "\(address)")
        }
        for address in ["http://192.168.1.20/v1", "http://mac-mini.local/v1", "https://api.example.com/v1"] {
            #expect(!ServerAddress.isLoopback(try #require(URL(string: address))), "\(address)")
        }
    }

    @Test func theSameServerHasTheSameSchemeHostAndPort() throws {
        func same(_ a: String, _ b: String) throws -> Bool {
            ServerAddress.isSameServer(try #require(URL(string: a)), try #require(URL(string: b)))
        }
        #expect(try same("https://api.example.com/v1", "https://API.example.com/openai/v2"))
        #expect(try same("https://api.example.com/v1", "https://api.example.com:443/v1"))
        #expect(try same("http://localhost/v1", "http://localhost:80/v1"))
        #expect(try !same("https://api.example.com/v1", "https://api.example.org/v1"))
        #expect(try !same("http://localhost:11434/v1", "http://localhost:1234/v1"))
        #expect(try !same("http://studio.local/v1", "https://studio.local/v1"))
    }
}

@Suite struct CustomProviderTests {
    @Test func newProvidersGetTheirOwnIDs() {
        let first = CustomProvider(name: "Ollama", address: "http://localhost:11434/v1")
        let second = CustomProvider(name: "Ollama", address: "http://localhost:11434/v1")
        #expect(first.id != second.id)
        #expect(first.id.hasPrefix(CustomProvider.idPrefix))
        #expect(CustomProvider.isCustom(first.id))
        #expect(!CustomProvider.isCustom("openai"))
    }

    @Test func survivesEncodingAndKnowsItsServer() throws {
        let provider = CustomProvider(id: "custom-1", name: "Studio", address: "http://mac-mini.local:1234/v1")
        let decoded = try JSONDecoder().decode(CustomProvider.self, from: JSONEncoder().encode(provider))
        #expect(decoded == provider)
        #expect(provider.url == URL(string: "http://mac-mini.local:1234/v1"))
        #expect(!provider.isOnThisDevice)
        #expect(CustomProvider(name: "Ollama", address: "http://localhost:11434/v1").isOnThisDevice)
        #expect(CustomProvider(name: "Broken", address: "localhost").url == nil)
    }

    @Test func aKeyStaysWithTheServerItWasEnteredFor() {
        let gateway = CustomProvider(name: "Gateway", address: "https://ai.example.com/v1")
        var renamed = gateway
        renamed.name = "Work gateway"
        renamed.address = "https://ai.example.com/openai/v1"
        #expect(!CustomProvider.movesToAnotherServer(from: gateway, to: renamed), "a new name or path keeps the key")

        var moved = gateway
        moved.address = "https://free-models.example.net/v1"
        #expect(CustomProvider.movesToAnotherServer(from: gateway, to: moved))
        moved.address = "https://ai.example.com:8443/v1"
        #expect(CustomProvider.movesToAnotherServer(from: gateway, to: moved), "another port is another server")
        moved.address = "not an address"
        #expect(CustomProvider.movesToAnotherServer(from: gateway, to: moved))
    }
}
