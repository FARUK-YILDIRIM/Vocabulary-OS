import Foundation
import FoundationModels
import Testing
import VocabularyCore
@testable import VocabularyAI

@Suite struct OnDeviceAvailabilityTests {
    @Test func mapsEveryAvailabilityState() {
        #expect(OnDeviceAvailability(.available) == .available)
        #expect(OnDeviceAvailability(.unavailable(.deviceNotEligible)) == .deviceNotEligible)
        #expect(OnDeviceAvailability(.unavailable(.appleIntelligenceNotEnabled)) == .appleIntelligenceNotEnabled)
        #expect(OnDeviceAvailability(.unavailable(.modelNotReady)) == .modelNotReady)
    }

    @Test func unavailableStatesBecomeErrors() {
        #expect(OnDeviceAvailability.available.error == nil)
        #expect(OnDeviceAvailability.deviceNotEligible.error == .onDeviceUnavailable(.deviceNotEligible))
        #expect(OnDeviceAvailability.modelNotReady.error == .onDeviceUnavailable(.modelNotReady))
    }
}

@Suite struct MissingAssetsTests {
    @Test func recognizesMissingAssetsInUnderlyingErrors() {
        let assets = NSError(domain: "com.apple.UnifiedAssetFramework", code: 5000)
        let wrapped = NSError(domain: "FoundationModels.LanguageModelSession.GenerationError", code: -1, userInfo: [NSMultipleUnderlyingErrorsKey: [assets]])
        #expect(AppleOnDeviceClient.isMissingModelAssets(wrapped))
        #expect(!AppleOnDeviceClient.isMissingModelAssets(NSError(domain: "Other", code: 1)))
    }
}

@Suite struct GenerationErrorMappingTests {
    private let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")

    @Test func mapsGenerationErrors() {
        typealias GenerationError = LanguageModelSession.GenerationError
        #expect(AIError(GenerationError.exceededContextWindowSize(context)) == .contextTooLong)
        #expect(AIError(GenerationError.assetsUnavailable(context)) == .onDeviceUnavailable(.modelNotReady))
        #expect(AIError(GenerationError.guardrailViolation(context)) == .guardrailViolation)
        #expect(AIError(GenerationError.unsupportedLanguageOrLocale(context)) == .unsupportedLanguage)
        #expect(AIError(GenerationError.decodingFailure(context)) == .invalidOutput("The model's answer didn't match the expected format."))
        #expect(AIError(GenerationError.rateLimited(context)) == .rateLimited)
        #expect(AIError(GenerationError.concurrentRequests(context)) == .busy)
        #expect(AIError(GenerationError.unsupportedGuide(context)) == .invalidOutput("The request used a constraint the model doesn't support."))
        #expect(AIError(GenerationError.refusal(.init(transcriptEntries: []), context)) == .refusal)
    }

    @Test func everyErrorHasAUserFacingDescription() {
        let errors: [AIError] = [
            .onDeviceUnavailable(.deviceNotEligible), .onDeviceUnavailable(.appleIntelligenceNotEnabled),
            .onDeviceUnavailable(.modelNotReady), .unsupportedLanguage, .contextTooLong, .guardrailViolation,
            .refusal, .rateLimited, .busy, .invalidOutput("x"), .missingAPIKey, .missingEndpoint, .invalidAPIKey, .quotaExceeded, .modelUnavailable,
            .network("offline"), .server(status: 503), .cancelled, .unknown("x"),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false, "\(error)")
        }
    }
}

/// Talks to the real on-device model. Opt in with `VOS_LIVE_MODEL=1 swift test --filter Live`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["VOS_LIVE_MODEL"] == "1"))
struct LiveAppleOnDeviceClientTests {
    @Generable
    struct Classification {
        @Guide(description: "The language of the sentence", .anyOf(["English", "German", "Turkish"]))
        var language: String
    }

    @Test func generatesAGenerableValueOnThisMac() async throws {
        let client = AppleOnDeviceClient()
        try #require(client.availability == .available, "Apple Intelligence is not available on this machine")
        let result = try await client.generate(
            GenerationRequest(instructions: "Identify languages.", prompt: "Sentence: \"Wir saßen auf einer Bank im Park.\""),
            as: Classification.self
        )
        #expect(result.language == "German")
    }
}
