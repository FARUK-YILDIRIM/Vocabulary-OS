import Foundation
import os
import VocabularyCore

/// A word saved in the Share extension, waiting for the app to import it (ADR-002).
public struct CaptureDraft: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var insight: WordInsight
    public var captureSource: CaptureSource
    public var savedAt: Date

    public init(id: UUID = UUID(), insight: WordInsight, captureSource: CaptureSource, savedAt: Date = Date()) {
        self.id = id
        self.insight = insight
        self.captureSource = captureSource
        self.savedAt = savedAt
    }
}

/// JSON files in the App Group container that hand captures from the Share extension to the app.
///
/// The extension never opens the CloudKit-synced store: Apple advises that only the app syncs, and
/// SQLite locks held across process suspension get extensions terminated (ADR-002). Each draft is one
/// atomically written file, so a half-written capture can't corrupt the others.
public struct CaptureInbox: Sendable {
    public let directory: URL
    private static let logger = Logger(subsystem: VocabularyCore.logSubsystem, category: VocabularyData.logCategory)

    public init(directory: URL) {
        self.directory = directory
    }

    /// The inbox inside an App Group container, or `nil` when the group isn't available (unsigned builds
    /// without the App Group entitlement).
    public static func appGroup(_ identifier: String) -> CaptureInbox? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            .map { CaptureInbox(directory: $0.appending(path: "Inbox", directoryHint: .isDirectory)) }
    }

    public func write(_ draft: CaptureDraft) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: url(for: draft.id), options: .atomic)
    }

    /// Drafts waiting to be imported, oldest first. Unreadable files are deleted and logged.
    public func pending() -> [CaptureDraft] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        var drafts: [CaptureDraft] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let draft = try? decoder.decode(CaptureDraft.self, from: data) {
                drafts.append(draft)
            } else {
                Self.logger.error("Discarding unreadable inbox file \(file.lastPathComponent, privacy: .public)")
                try? FileManager.default.removeItem(at: file)
            }
        }
        return drafts.sorted { $0.savedAt < $1.savedAt }
    }

    public func remove(_ id: UUID) throws {
        let file = url(for: id)
        if FileManager.default.fileExists(atPath: file.path()) {
            try FileManager.default.removeItem(at: file)
        }
    }

    /// Saves every pending draft to the library and removes it from the inbox. Returns how many were
    /// imported. A draft that fails to save stays in the inbox for the next attempt.
    @MainActor
    @discardableResult
    public static func importPending(from inbox: CaptureInbox, into repository: WordRepository) -> Int {
        var imported = 0
        for draft in inbox.pending() {
            do {
                try repository.save(draft.insight, captureSource: draft.captureSource)
                try inbox.remove(draft.id)
                imported += 1
            } catch {
                logger.error("Could not import a captured word: \(error.localizedDescription, privacy: .public)")
            }
        }
        return imported
    }

    private func url(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
