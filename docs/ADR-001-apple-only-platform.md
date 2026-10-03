# ADR-001: Apple-only platform, iOS/iPadOS/macOS 26 minimum

## Status
Accepted (revised 2026-10-04: minimum OS and facts corrected)

## Date
2026-10-03

## Context
Vocabulary-OS captures words where people read and reinforces them with AI-generated practice. The
owner decided to build only for the Apple ecosystem and to rely on what the platform offers instead
of running a server:
- on-device AI;
- iCloud sync;
- text recognition;
- speech;
- share extensions.

The first version of this ADR said Foundation Models needs iOS 18.2 and that base features need
iOS 16. Neither is true. Foundation Models (`SystemLanguageModel`, `LanguageModelSession`) is
annotated `@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)` in the 26.2 SDK. The on-device model
is the app's default AI, so it sets the minimum OS.

## Decision
- Build one multiplatform SwiftUI app for **iPhone, iPad and Mac**. There is no Android, Windows or
  web version.
- Minimum OS: **iOS 26.0, iPadOS 26.0, macOS 26.0**. Build with Xcode 26.2 or newer and Swift 6.2.
- Devices that run iOS 26 but are not eligible for Apple Intelligence still run the app. AI features
  ask the user to connect a cloud provider with their own key (see ADR-003).

## Alternatives Considered
- **Cross-platform UI (Flutter, React Native):**
  - Pros: one codebase for Android too.
  - Cons: share extensions, Vision, Foundation Models, SwiftData/CloudKit and speech would each need
    native bridges.
  - Rejected: the owner chose Apple-only, and the product is built on these frameworks.
- **iOS 17/18 minimum with on-device AI only on 26:**
  - Pros: reaches older devices.
  - Cons: two AI code paths, plus older Vision and SwiftData APIs. `RecognizeDocumentsRequest`
    (paragraphs with word boxes) is iOS/macOS 26 only.
  - Rejected for an open-source project maintained mostly by AI agents, where one code path matters
    more than reach.

## Consequences
- One code path and the newest APIs: `@Observable`, the Swift Vision API, Foundation Models and the
  SwiftData history APIs.
- Users on iOS 25 or older cannot install the app.
- On non-Apple-Intelligence devices, the default AI is unavailable until a cloud key is added. The UI
  must explain this.
- iCloud sync needs a paid Apple Developer Program membership for signing. Contributors without one
  can still build and run locally without sync (ADR-006).

## Sources
- Foundation Models availability annotations: `FoundationModels.swiftinterface` in the iOS/macOS 26.2
  SDK.
- Vision `RecognizeDocumentsRequest` availability: `Vision.swiftinterface` in the macOS 26.2 SDK.
- Apple Intelligence language support and device eligibility:
  https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models
