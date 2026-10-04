import Foundation
import SwiftData

/// Creates the app's model container (ADR-002).
///
/// There is no versioned schema yet. After the first release, model changes must be additive (the
/// production CloudKit schema can't drop fields), and SwiftData migrates added properties and models
/// on its own. If a change ever needs a migration stage, `SchemaV1` comes then, with frozen copies of
/// the models as they shipped, next to `SchemaV2` (SPEC Boundaries, "ask first"). A versioned schema
/// that listed these live classes would stop matching the shipped store at the first change.
public enum VocabularyStore {
    public static var models: [any PersistentModel.Type] {
        [VocabularyEntry.self, WordList.self, ReviewLog.self, QuizRecord.self, PodcastEpisode.self, StudyPlan.self]
    }

    public static var schema: Schema { Schema(models) }

    /// - Parameters:
    ///   - inMemory: For tests and previews.
    ///   - cloudSync: Sync with the iCloud container from the app's entitlements. Builds without the
    ///     entitlement pass `false` and keep data on the device.
    public static func makeContainer(inMemory: Bool = false, cloudSync: Bool) throws -> ModelContainer {
        try makeContainer(
            ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                // The Share extension never opens this store; it hands captures over through the inbox.
                groupContainer: .none,
                cloudKitDatabase: cloudSync ? .automatic : .none
            )
        )
    }

    /// A store at a given place on disk; for tests that reopen it.
    static func makeContainer(url: URL, cloudSync: Bool) throws -> ModelContainer {
        try makeContainer(ModelConfiguration(schema: schema, url: url, cloudKitDatabase: cloudSync ? .automatic : .none))
    }

    private static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: configuration)
    }
}

/// CloudKit's rules for synced models (ADR-002). Breaking one only fails at runtime, with a real
/// iCloud account, so tests run this check against the app's schema.
public enum CloudKitSchemaRules {
    /// Human-readable rule violations; empty when the schema can sync.
    public static func violations(in schema: Schema) -> [String] {
        var problems: [String] = []
        for entity in schema.entities {
            if !entity.uniquenessConstraints.isEmpty {
                problems.append("\(entity.name) has a uniqueness constraint")
            }
            for attribute in entity.attributes {
                if attribute.isUnique {
                    problems.append("\(entity.name).\(attribute.name) is unique")
                }
                if !attribute.isOptional && attribute.defaultValue == nil {
                    problems.append("\(entity.name).\(attribute.name) needs a default value or must be optional")
                }
            }
            for relationship in entity.relationships {
                if !relationship.isOptional {
                    problems.append("\(entity.name).\(relationship.name) must be optional")
                }
                if relationship.inverseName == nil && relationship.inverseKeyPath == nil {
                    problems.append("\(entity.name).\(relationship.name) needs an inverse")
                }
                if relationship.deleteRule == .deny {
                    problems.append("\(entity.name).\(relationship.name) uses the unsupported .deny rule")
                }
            }
        }
        return problems.sorted()
    }
}
