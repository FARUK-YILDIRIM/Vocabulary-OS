import Foundation
import FoundationModels

/// Why the on-device model can't run (mirrors `SystemLanguageModel.Availability`).
public enum OnDeviceUnavailableReason: Hashable, Sendable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
}

/// Every way an AI request can fail, with messages the UI can show as they are (ADR-003).
///
/// Associated strings are diagnostic summaries and never contain the learner's text or API keys.
public enum AIError: Error, Hashable, Sendable, LocalizedError {
    case onDeviceUnavailable(OnDeviceUnavailableReason)
    case unsupportedLanguage
    case contextTooLong
    case guardrailViolation
    case refusal
    case rateLimited
    case busy
    case invalidOutput(String)
    case missingAPIKey
    case invalidAPIKey
    case quotaExceeded
    case modelUnavailable
    case network(String)
    case server(status: Int)
    case cancelled
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .onDeviceUnavailable(.deviceNotEligible):
            String(localized: "This device can't run Apple's on-device model. Connect an AI provider in Settings.", bundle: .module)
        case .onDeviceUnavailable(.appleIntelligenceNotEnabled):
            String(localized: "Turn on Apple Intelligence in System Settings to use the on-device model, or connect an AI provider.", bundle: .module)
        case .onDeviceUnavailable(.modelNotReady):
            String(localized: "The on-device model is still downloading. Try again in a few minutes.", bundle: .module)
        case .unsupportedLanguage:
            String(localized: "The on-device model doesn't support this language yet. Connect an AI provider in Settings.", bundle: .module)
        case .contextTooLong:
            String(localized: "The text is too long for the model. Try a shorter selection.", bundle: .module)
        case .guardrailViolation:
            String(localized: "The model declined this text because of its safety rules.", bundle: .module)
        case .refusal:
            String(localized: "The model refused to answer this request.", bundle: .module)
        case .rateLimited:
            String(localized: "Too many requests right now. Wait a moment and try again.", bundle: .module)
        case .busy:
            String(localized: "The model is busy with another request. Try again.", bundle: .module)
        case .invalidOutput:
            String(localized: "The model's answer wasn't usable. Try again.", bundle: .module)
        case .missingAPIKey:
            String(localized: "Add an API key for this provider in Settings.", bundle: .module)
        case .invalidAPIKey:
            String(localized: "The provider rejected the API key. Check it in Settings.", bundle: .module)
        case .quotaExceeded:
            String(localized: "Your provider account is out of credit or over its limit.", bundle: .module)
        case .modelUnavailable:
            String(localized: "This model isn't available for your key. Choose another model in Settings.", bundle: .module)
        case .network:
            String(localized: "The provider couldn't be reached. Check your connection.", bundle: .module)
        case .server(let status):
            String(localized: "The provider had a problem (HTTP \(status)). Try again later.", bundle: .module)
        case .cancelled:
            String(localized: "The request was cancelled.", bundle: .module)
        case .unknown:
            String(localized: "Something went wrong with the AI request.", bundle: .module)
        }
    }

    /// Maps the on-device framework's errors (ADR-003).
    init(_ error: LanguageModelSession.GenerationError) {
        switch error {
        case .exceededContextWindowSize: self = .contextTooLong
        case .assetsUnavailable: self = .onDeviceUnavailable(.modelNotReady)
        case .guardrailViolation: self = .guardrailViolation
        case .unsupportedLanguageOrLocale: self = .unsupportedLanguage
        case .decodingFailure: self = .invalidOutput("The model's answer didn't match the expected format.")
        case .rateLimited: self = .rateLimited
        case .concurrentRequests: self = .busy
        case .unsupportedGuide: self = .invalidOutput("The request used a constraint the model doesn't support.")
        case .refusal: self = .refusal
        @unknown default: self = .unknown(String(describing: error))
        }
    }
}
