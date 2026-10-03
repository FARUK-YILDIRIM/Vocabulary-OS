import Foundation
import FoundationModels
import VocabularyCore

/// Whether Apple's on-device model can run here.
public enum OnDeviceAvailability: Hashable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady

    init(_ availability: SystemLanguageModel.Availability) {
        switch availability {
        case .available: self = .available
        case .unavailable(.deviceNotEligible): self = .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): self = .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady): self = .modelNotReady
        case .unavailable: self = .modelNotReady
        }
    }

    /// The error to report when a request is made in this state, or `nil` when the model can run.
    public var error: AIError? {
        switch self {
        case .available: nil
        case .deviceNotEligible: .onDeviceUnavailable(.deviceNotEligible)
        case .appleIntelligenceNotEnabled: .onDeviceUnavailable(.appleIntelligenceNotEnabled)
        case .modelNotReady: .onDeviceUnavailable(.modelNotReady)
        }
    }
}

/// Apple's on-device foundation model: free, private, offline, no key (ADR-003).
///
/// Each request runs in a fresh session, so tasks never share context. The model is small (about
/// 3B parameters): callers keep prompts focused and split larger jobs into steps.
public struct AppleOnDeviceClient: GenerationClient {
    private let model: SystemLanguageModel

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    public var availability: OnDeviceAvailability {
        OnDeviceAvailability(model.availability)
    }

    /// Whether the model handles this language. Apple's list follows Apple Intelligence languages.
    public func supports(_ language: LanguageCode) -> Bool {
        model.supportsLocale(language.locale)
    }

    public func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent {
        if let error = availability.error {
            throw error
        }
        let session = LanguageModelSession(model: model, instructions: request.instructions)
        let options = GenerationOptions(
            sampling: request.isGreedy ? .greedy : nil,
            temperature: request.temperature,
            maximumResponseTokens: request.maximumResponseTokens
        )
        do {
            return try await session.respond(to: request.prompt, schema: schema, options: options).content
        } catch let error as LanguageModelSession.GenerationError {
            throw AIError(error)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            // Internal framework errors (seen with regex guides) carry no actionable detail.
            throw .unknown(String(describing: type(of: error)))
        }
    }
}
