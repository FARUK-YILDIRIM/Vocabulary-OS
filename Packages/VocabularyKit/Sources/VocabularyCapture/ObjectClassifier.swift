import Foundation
import ImageIO
import os
import Vision
import VocabularyCore

/// What Vision thinks a photo shows: one of its taxonomy labels, such as `cup`.
public struct ObjectLabel: Sendable, Hashable, Identifiable {
    public let identifier: String
    public let confidence: Float

    public var id: String { identifier }

    /// The label as plain English words, e.g. "swivel chair" for `swivel_chair`.
    public var name: String {
        identifier.replacingOccurrences(of: "_", with: " ")
    }

    public init(identifier: String, confidence: Float) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

/// Labels for a photographed object, with Vision's on-device image classifier (ADR-005).
public struct ObjectClassifier: Sendable {
    /// Weaker labels are mostly wrong (ADR-005).
    public static let minimumConfidence: Float = 0.3
    public static let maximumLabels = 5

    /// Taxonomy labels that group things rather than name one. Vision returns them with the same
    /// confidence as the specific label below them ("utensil", "tableware", "cup"), so they are
    /// listed after the specific labels.
    static let categories: Set<String> = [
        "adult", "aircraft", "animal", "appliance", "art", "baked_goods", "celebration", "clothing",
        "consumer_electronics", "container", "conveyance", "cookware", "decoration", "dessert", "document",
        "food", "footwear", "furniture", "games", "housewares", "illustrations", "insect", "interior_room",
        "land", "liquid", "machine", "mammal", "material", "media", "music", "musical_instrument",
        "office_supplies", "outdoor", "people", "plant", "recreation", "reptile", "sport", "sports_equipment",
        "string_instrument", "structure", "tableware", "textile", "tool", "utensil", "vehicle", "watercraft",
    ]

    private static let logger = Logger(subsystem: VocabularyCore.logSubsystem, category: VocabularyCapture.logCategory)

    public init() {}

    /// The likeliest labels for the photo in image file data, most specific first; empty when
    /// nothing is recognized with enough confidence.
    public func labels(for imageData: Data) async throws(CaptureError) -> [ObjectLabel] {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw .unreadableImage
        }
        let observations: [ClassificationObservation]
        do {
            observations = try await ClassifyImageRequest().perform(on: imageData)
        } catch {
            if Task.isCancelled {
                throw .cancelled
            }
            Self.logger.error("Object classification failed: \(error.localizedDescription, privacy: .public)")
            throw .recognitionFailed
        }
        return Self.rank(observations.map { ($0.identifier, $0.confidence) })
    }

    /// Keeps confident labels, puts named things before categories, and caps the list.
    static func rank(_ candidates: [(identifier: String, confidence: Float)]) -> [ObjectLabel] {
        let confident = candidates
            .filter { $0.confidence >= minimumConfidence }
            .map { ObjectLabel(identifier: $0.identifier, confidence: $0.confidence) }
        let things = confident.filter { !categories.contains($0.identifier) }
        let groups = confident.filter { categories.contains($0.identifier) }
        // Sorting is stable, so labels with equal confidence keep Vision's order.
        let ranked = things.sorted { $0.confidence > $1.confidence } + groups.sorted { $0.confidence > $1.confidence }
        return Array(ranked.prefix(maximumLabels))
    }
}
