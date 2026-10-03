# Claude Agent Instructions for Vocabulary-OS

This file specifies how AI agents should approach development of Vocabulary-OS.

## Core Principles

1. **Privacy-first:** No user data leaves the device except via CloudKit (to user's iCloud). Never log tokens, credentials, or user content.
2. **Offline-first:** App must work offline; sync happens automatically when online.
3. **Zero backend:** No server code. All business logic runs on-device.
4. **Swift + SwiftUI only:** Single language, single framework. No Objective-C, no storyboards.
5. **Test everything:** Unit tests for logic, UI tests for flows. Aim for >80% code coverage.
6. **Build incrementally:** One milestone at a time; each is a shippable feature.

## Code Style

- **Swift 6.2+:** Use latest language features (strict concurrency, Actor, Sendable)
- **SwiftUI:** Declarative UI, no UIKit wrappers
- **Naming:** CamelCase for types, camelCase for variables; avoid abbreviations
- **Comments:** Explain "why", not "what" (code is clear, intent may not be)
- **Error handling:** Use custom `Error` types, no force unwrapping (`!`)

### Example Code Structure

```swift
// ✓ Good
enum WordCaptureError: Error {
    case emptyWord
    case invalidLanguage(String)
}

// ✗ Bad
enum Error: Error {
    case error
}
// ✗ Bad: force unwrap
let word = words.first!
```

## Architecture

### Package Structure

```
Vocabulary-OS/
├── Vocabulary-OS/          # iOS app target
├── Vocabulary-macOS/       # macOS app target (shared SwiftUI code)
├── VocabularyCoreKit/      # Shared frameworks (Swift Package)
│   ├── VocabularyCoreKit/  # Data models, domain logic
│   ├── VocabularyAIKit/    # LLM provider abstraction
│   ├── VocabularyStoreKit/ # SwiftData + CloudKit
│   └── VocabularyUIKit/    # Shared SwiftUI components
└── Tests/                  # Unit + UI tests
```

### Dependency Rules

- **Strict:** No circular dependencies between packages
- **Presentation layer:** Can import all others; imports SwiftUI
- **Domain logic:** Cannot import SwiftUI or network frameworks
- **Data layer:** Cannot import SwiftUI or domain logic

### Forbidden

- `DispatchQueue.main.async` (use `@MainActor` instead)
- `URLSession` (use only in dedicated adapters with async/await)
- `.ignore()` error handling (catch and handle, or propagate with meaningful error)
- `print()` (use a logging framework or debug assertions)
- Optionals without handling (use `guard let`, `if let`, or `??` with clear intent)

## Testing

### Test Coverage Targets

- **Domain logic:** 100% (SM-2, language detection, AI provider interface)
- **Data models:** 100% (CRUD, relationships, validation)
- **SwiftUI views:** 50%+ (snapshot tests, navigation tests)
- **Integration:** 30%+ (sync, AI providers, file I/O)

### Test File Naming

- Logic test: `[Feature]Tests.swift` (e.g., `SM2AlgorithmTests.swift`)
- UI test: `[Feature]UITests.swift` (e.g., `CaptureFlowUITests.swift`)
- Mock test: In same file or `Mocks/[Feature]Mock.swift`

### Example Test

```swift
import XCTest
@testable import VocabularyCoreKit

final class WordCaptureTests: XCTestCase {
    func testCaptureValidWord() async throws {
        let word = Word(text: "serendipity", context: "A fortunate stroke of serendipity")
        
        XCTAssertEqual(word.text, "serendipity")
        XCTAssertTrue(word.context.contains("serendipity"))
    }
}
```

## Building & Running

### Commands

```bash
# Install dependencies
swift package resolve

# Build
swift build

# Test
swift test

# Run iOS app
xcode-select -p
open Vocabulary-OS.xcodeproj
# Then build in Xcode

# Run macOS app
# Same project, select Vocabulary-macOS scheme

# Type-check
swift build --build-tests
```

### Required Environment

- **Swift:** 6.2+
- **macOS:** 14+
- **Xcode:** 15+
- **iOS minimum:** 16 (base), 18.2+ (Foundation Models)
- **macOS minimum:** 13

## Git Workflow

### Commits

Every commit message must include:

```
[Feature name]: brief description

- Detailed explanation of what changed
- Why this change was made
- Related ADR (if applicable)

Co-Authored-By: Claude [Model] <noreply@anthropic.com>
```

Example:

```
[M1-DataModels]: add Word and Collection SwiftData models

- Word model stores: text, context, sourceLanguage, image, retention score
- Collection model stores: words (1:many), language, sharing metadata
- Added CRUD unit tests (12 tests)
- Validated CloudKit compatibility

Related: docs/ADR-002-cloudkit-private-data-architecture.md

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

### PR Template (when needed)

```
## Milestone
M[X]: [Feature name]

## Summary
[What was built]

## Acceptance Criteria
- [x] Criterion 1
- [x] Criterion 2
- [ ] Criterion 3 (if not met, explain why)

## Testing
- [X] Unit tests pass
- [X] UI tests pass
- [X] Manual testing on iOS simulator
- [ ] Manual testing on macOS (if applicable)

## Screenshots / Video
[If UI changes, include screenshot]
```

## Debugging

### Logging

Use `os.log` (not `print`):

```swift
import os

private let logger = Logger(subsystem: "com.vocab.core", category: "DataSync")

logger.info("Syncing \(words.count) words to CloudKit")
logger.error("Sync failed: \(error.localizedDescription)")
```

### Common Issues

- **CloudKit sync not working:** Check iCloud account login in Simulator settings
- **SwiftData queries slow:** Profile with Instruments (Core Data tool)
- **AI provider timeout:** Check network, increase timeout if legitimate latency

## Asking for Help

When stuck, provide:
1. Error message (full stack trace)
2. Minimal reproducible example (code snippet)
3. What you've tried
4. Which ADR or milestone this relates to

Example:

```
[M5-Vision] Document scanning fails on device

Error: VNRecognizeTextRequest returned nil when processing JPEG

Tried:
- Checking image orientation
- Validating JPEG format
- Different image sizes

Related: docs/ADR-005-vision-and-object-capture.md

Code:
let request = VNRecognizeTextRequest()
let handler = VNImageRequestHandler(cgImage: image)
try handler.perform([request])
// request.results is nil
```

## Resources

- [SwiftUI documentation](https://developer.apple.com/documentation/swiftui)
- [CloudKit documentation](https://developer.apple.com/documentation/cloudkit)
- [SwiftData documentation](https://developer.apple.com/documentation/swiftdata)
- [Vision framework](https://developer.apple.com/documentation/vision)
- Project ADRs: [`docs/`](docs)
- Specification: [`SPEC.md`](SPEC.md)
- Milestones: [`MILESTONES.md`](MILESTONES.md)
