#if DEBUG
import CoreData
import Foundation
import SwiftData
import VocabularyData

/// Creates every record type and field of the word store in CloudKit's development environment
/// (`-vos-self-test cloudkit-schema`, signed builds only).
///
/// SwiftData only creates the fields it has saved a value for, while TestFlight and App Store builds
/// use the production environment, whose schema is deployed from the development one in the CloudKit
/// Console (ADR-002). This follows Apple's "Syncing model data across a person's devices": a Core
/// Data container with the same model initializes the schema, on a store of its own.
enum CloudKitSchemaSetup {
    enum SetupError: Error, LocalizedError {
        case noBundleIdentifier
        case noModel

        var errorDescription: String? {
            switch self {
            case .noBundleIdentifier: "The app has no bundle identifier."
            case .noModel: "The SwiftData models couldn't be turned into a Core Data model."
            }
        }
    }

    static func initialize() async throws {
        // The container is iCloud.<bundle ID prefix>, and the app's bundle ID is that prefix
        // (Config/Base.xcconfig).
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { throw SetupError.noBundleIdentifier }
        let containerIdentifier = "iCloud." + bundleIdentifier
        try await Task.detached {
            try autoreleasepool {
                try initialize(containerIdentifier: containerIdentifier)
            }
        }.value
    }

    /// Runs off the main actor: it talks to CloudKit and can take a while.
    nonisolated private static func initialize(containerIdentifier: String) throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: VocabularyStore.models) else {
            throw SetupError.noModel
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "cloudkit-schema-\(UUID().uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        // Loaded synchronously, so the store is ready before the schema is initialized.
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "VocabularyOS", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        try container.initializeCloudKitSchema(options: [])

        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix))
        }
    }
}
#endif
