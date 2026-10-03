import Foundation
import VocabularyCore
import VocabularyData

/// Saves captures made in the Share extension to the App Group inbox, for the app to import (ADR-002).
public struct InboxCaptureDestination: CaptureDestination {
    private let inbox: CaptureInbox

    public init(inbox: CaptureInbox) {
        self.inbox = inbox
    }

    /// The extension can't read the library, so it only knows about words still waiting in the inbox.
    public func savedTranslation(lemma: String, language: LanguageCode) -> String? {
        let key = lemma.matchingKey
        return inbox.pending().last { $0.insight.lemma.matchingKey == key && $0.insight.language == language }?.insight.translation
    }

    public func save(_ insight: WordInsight, captureSource: CaptureSource) throws {
        try inbox.write(CaptureDraft(insight: insight, captureSource: captureSource))
    }
}
