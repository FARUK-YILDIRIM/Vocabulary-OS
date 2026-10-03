/// Which AI provider and model the learner uses (ADR-003).
///
/// Provider IDs are defined by the AI module's catalog; this type only carries them, so settings can
/// sync without depending on the AI module. API keys are never part of a selection.
public struct AIProviderSelection: Hashable, Codable, Sendable {
    public var providerID: String
    public var modelID: String?

    public init(providerID: String, modelID: String? = nil) {
        self.providerID = providerID
        self.modelID = modelID
    }

    /// The default: Apple's on-device model, which needs no key (ADR-003).
    public static let onDevice = AIProviderSelection(providerID: "apple-on-device")
}

/// How many new words and reviews Today offers per day (ADR-007).
public struct ReviewLimits: Hashable, Codable, Sendable {
    public static let newPerDayRange = 0...200
    public static let reviewsPerDayRange = 1...2_000

    public private(set) var newPerDay: Int
    public private(set) var reviewsPerDay: Int

    public init(newPerDay: Int = 15, reviewsPerDay: Int = 150) {
        self.newPerDay = newPerDay.clamped(to: Self.newPerDayRange)
        self.reviewsPerDay = reviewsPerDay.clamped(to: Self.reviewsPerDayRange)
    }

    private enum CodingKeys: String, CodingKey {
        case newPerDay, reviewsPerDay
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            newPerDay: try container.decode(Int.self, forKey: .newPerDay),
            reviewsPerDay: try container.decode(Int.self, forKey: .reviewsPerDay)
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
