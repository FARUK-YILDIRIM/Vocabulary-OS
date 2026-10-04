import Foundation
import SwiftData

/// The first schema version.
///
/// Before the first public release this schema may still change. After the release, model changes
/// must be additive (the production CloudKit schema can't drop fields) and go into `SchemaV2` with a
/// migration stage (ADR-002, SPEC Boundaries "ask first").
public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [VocabularyEntry.self, WordList.self, ReviewLog.self]
    }
}

public enum VocabularyMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

/// Creates the app's model container (ADR-002).
public enum VocabularyStore {
    /// - Parameters:
    ///   - inMemory: For tests and previews.
    ///   - cloudSync: Sync with the iCloud container from the app's entitlements. Builds without the
    ///     entitlement pass `false` and keep data on the device.
    public static func makeContainer(inMemory: Bool = false, cloudSync: Bool) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            // The Share extension never opens this store; it hands captures over through the inbox.
            groupContainer: .none,
            cloudKitDatabase: cloudSync ? .automatic : .none
        )
        return try ModelContainer(for: schema, migrationPlan: VocabularyMigrationPlan.self, configurations: configuration)
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
