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
    /// Where drafts this version can't read are kept, perhaps for a later version.
    public static let unreadableFolder = "Unreadable"

    public let directory: URL
    private static let logger = Logger(subsystem: VocabularyCore.logSubsystem, category: VocabularyData.logCategory)

    public init(directory: URL) {
        self.directory = directory
    }

    public func write(_ draft: CaptureDraft) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Sentences can come from private mail. The extension writes and the app reads drafts only
        // while the device is unlocked, so they can be locked away otherwise (security review).
        #if os(iOS)
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]
        #else
        let options: Data.WritingOptions = .atomic
        #endif
        try JSONEncoder().encode(draft).write(to: url(for: draft.id), options: options)
    }

    /// Drafts waiting to be imported, oldest first. A file this version can't read, perhaps from a
    /// newer extension, is moved to `unreadableFolder` and logged, never deleted.
    public func pending() -> [CaptureDraft] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        var drafts: [CaptureDraft] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let draft = try? decoder.decode(CaptureDraft.self, from: data) {
                drafts.append(draft)
            } else {
                Self.logger.error("Setting aside unreadable inbox file \(file.lastPathComponent, privacy: .public)")
                setAside(file)
            }
        }
        return drafts.sorted { $0.savedAt < $1.savedAt }
    }

    private func setAside(_ file: URL) {
        let folder = directory.appending(path: Self.unreadableFolder)
        let destination = folder.appending(path: file.lastPathComponent)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: file, to: destination)
    }

    public func remove(_ id: UUID) throws {
        let file = url(for: id)
        if FileManager.default.fileExists(atPath: file.path()) {
            try FileManager.default.removeItem(at: file)
        }
    }

    /// Saves every pending draft to the library and removes it from the inbox. Returns how many were
    /// imported. A word the library already has is not saved again: the extension can't see the
    /// library to warn the learner (SPEC C4). A draft that fails to save stays in the inbox for the
    /// next attempt.
    @MainActor
    @discardableResult
    public static func importPending(from inbox: CaptureInbox, into repository: WordRepository) -> Int {
        var imported = 0
        for draft in inbox.pending() {
            do {
                if try repository.existingEntry(lemma: draft.insight.lemma, language: draft.insight.language) == nil {
                    try repository.save(draft.insight, captureSource: draft.captureSource)
                    imported += 1
                }
                try inbox.remove(draft.id)
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
