// swift-tools-version: 6.2
import PackageDescription

// All non-app code lives here so it can be tested on the Mac host with `swift test` (ADR-006).
// Dependency direction: Core ← AI, Data, Capture, Speech ← UI.
let package = Package(
    name: "VocabularyKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "VocabularyCore", targets: ["VocabularyCore"]),
        .library(name: "VocabularyAI", targets: ["VocabularyAI"]),
        .library(name: "VocabularyData", targets: ["VocabularyData"]),
        .library(name: "VocabularyCapture", targets: ["VocabularyCapture"]),
        .library(name: "VocabularySpeech", targets: ["VocabularySpeech"]),
        .library(name: "VocabularyUI", targets: ["VocabularyUI"]),
    ],
    targets: [
        .target(name: "VocabularyCore"),
        .target(name: "VocabularyAI", dependencies: ["VocabularyCore"]),
        .target(name: "VocabularyData", dependencies: ["VocabularyCore"]),
        .target(name: "VocabularyCapture", dependencies: ["VocabularyCore"]),
        .target(name: "VocabularySpeech", dependencies: ["VocabularyCore"]),
        .target(
            name: "VocabularyUI",
            dependencies: ["VocabularyCore", "VocabularyAI", "VocabularyData", "VocabularyCapture", "VocabularySpeech"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "VocabularyCoreTests", dependencies: ["VocabularyCore"]),
        .testTarget(name: "VocabularyAITests", dependencies: ["VocabularyAI"]),
        .testTarget(name: "VocabularyDataTests", dependencies: ["VocabularyData"]),
        .testTarget(name: "VocabularyCaptureTests", dependencies: ["VocabularyCapture"]),
        .testTarget(name: "VocabularySpeechTests", dependencies: ["VocabularySpeech"]),
        .testTarget(name: "VocabularyUITests", dependencies: ["VocabularyUI"]),
    ],
    swiftLanguageModes: [.v6]
)
