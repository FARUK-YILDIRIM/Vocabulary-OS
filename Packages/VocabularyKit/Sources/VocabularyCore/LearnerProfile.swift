import Foundation

/// The learner's native language and the ordered languages they study (SPEC C1, ADR-004).
///
/// Invariants: every language is in `LanguageCatalog`, learning languages are unique, and the native
/// language is never a learning language. Removing a learning language never touches saved words;
/// they keep their language and reappear when it is added back.
public struct LearnerProfile: Hashable, Sendable, Codable {
    public private(set) var native: LanguageCode
    public private(set) var learning: [LanguageCode]

    public init(native: LanguageCode, learning: [LanguageCode]) throws(LearnerProfileError) {
        guard LanguageCatalog.contains(native) else { throw .unsupported(native) }
        self.native = native
        self.learning = []
        for code in learning {
            try addLearning(code)
        }
    }

    /// Learning needs at least one learning language; onboarding is complete when this is true.
    public var isReadyToLearn: Bool { !learning.isEmpty }

    public mutating func addLearning(_ code: LanguageCode) throws(LearnerProfileError) {
        guard LanguageCatalog.contains(code) else { throw .unsupported(code) }
        guard code != native else { throw .nativeCannotBeLearning(code) }
        guard !learning.contains(code) else { throw .duplicate(code) }
        learning.append(code)
    }

    public mutating func removeLearning(_ code: LanguageCode) {
        learning.removeAll { $0 == code }
    }

    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`: `destination` is an index in the
    /// list before the move.
    public mutating func moveLearning(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().compactMap { learning.indices.contains($0) ? learning[$0] : nil }
        var remaining = learning.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertion = destination - source.count(in: 0..<destination)
        remaining.insert(contentsOf: moving, at: min(max(insertion, 0), remaining.count))
        learning = remaining
    }

    /// Switching the native language to one being learned removes it from the learning list.
    public mutating func setNative(_ code: LanguageCode) throws(LearnerProfileError) {
        guard LanguageCatalog.contains(code) else { throw .unsupported(code) }
        native = code
        learning.removeAll { $0 == code }
    }

    private enum CodingKeys: String, CodingKey {
        case native, learning
    }

    /// Decoding re-checks the invariants, because synced or imported data may come from elsewhere.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            native: container.decode(LanguageCode.self, forKey: .native),
            learning: container.decode([LanguageCode].self, forKey: .learning)
        )
    }
}

public enum LearnerProfileError: Error, Equatable, Sendable, LocalizedError {
    case unsupported(LanguageCode)
    case duplicate(LanguageCode)
    case nativeCannotBeLearning(LanguageCode)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let code):
            String(localized: "\(code.localizedName()) isn't supported yet.", bundle: .module)
        case .duplicate(let code):
            String(localized: "\(code.localizedName()) is already one of your learning languages.", bundle: .module)
        case .nativeCannotBeLearning(let code):
            String(localized: "\(code.localizedName()) is your native language.", bundle: .module)
        }
    }
}
