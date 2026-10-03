// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Vocabulary-OS",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    dependencies: [
        // Testing
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.15.0"),
    ],
    targets: [
        // Core data models and domain logic
        .target(
            name: "VocabularyCoreKit",
            dependencies: [],
            path: "Packages/VocabularyCoreKit/Sources"
        ),
        .testTarget(
            name: "VocabularyCoreKitTests",
            dependencies: ["VocabularyCoreKit"],
            path: "Packages/VocabularyCoreKit/Tests"
        ),

        // AI provider abstraction
        .target(
            name: "VocabularyAIKit",
            dependencies: ["VocabularyCoreKit"],
            path: "Packages/VocabularyAIKit/Sources"
        ),
        .testTarget(
            name: "VocabularyAIKitTests",
            dependencies: ["VocabularyAIKit", "VocabularyCoreKit"],
            path: "Packages/VocabularyAIKit/Tests"
        ),

        // Data persistence (SwiftData + CloudKit)
        .target(
            name: "VocabularyStoreKit",
            dependencies: ["VocabularyCoreKit"],
            path: "Packages/VocabularyStoreKit/Sources"
        ),
        .testTarget(
            name: "VocabularyStoreKitTests",
            dependencies: ["VocabularyStoreKit", "VocabularyCoreKit"],
            path: "Packages/VocabularyStoreKit/Tests"
        ),

        // Shared UI components
        .target(
            name: "VocabularyUIKit",
            dependencies: ["VocabularyCoreKit", "VocabularyStoreKit"],
            path: "Packages/VocabularyUIKit/Sources"
        ),
        .testTarget(
            name: "VocabularyUIKitTests",
            dependencies: ["VocabularyUIKit", "VocabularyCoreKit"],
            path: "Packages/VocabularyUIKit/Tests"
        ),
    ]
)
