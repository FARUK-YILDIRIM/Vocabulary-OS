# Vocabulary-OS

**Privacy-first, multi-language learning app for Apple platforms.**

Capture words from text, books, and objects, then reinforce them with AI-generated podcasts, quizzes, and spaced repetition—all on your device, in your iCloud account.

## Quick Start

See [`SPEC.md`](SPEC.md) for features and [`MILESTONES.md`](MILESTONES.md) for development plan.

### Minimal Setup

```bash
git clone <repo>
cd Vocabulary-OS
swift package resolve
swift test
```

### Run iOS App

```bash
open Vocabulary-OS.xcodeproj
# Xcode → Select "Vocabulary-OS" scheme → Run
```

### Run macOS App

```bash
open Vocabulary-OS.xcodeproj
# Xcode → Select "Vocabulary-macOS" scheme → Run
```

## Architecture

Read [`docs/`](docs) for architectural decisions (ADRs):

- [ADR-001: Apple-only platform](docs/ADR-001-apple-only-platform.md)
- [ADR-002: CloudKit private data](docs/ADR-002-cloudkit-private-data-architecture.md)
- [ADR-003: BYOK AI providers](docs/ADR-003-byok-ai-provider-model.md)
- [ADR-004: Multi-language support](docs/ADR-004-multilingual-architecture.md)
- [ADR-005: Vision & object capture](docs/ADR-005-vision-and-object-capture.md)

## Development

### Packages

- **`VocabularyCoreKit`:** Data models (Word, Collection), domain logic (SM-2), language detection
- **`VocabularyAIKit`:** LLM provider abstraction, quiz/podcast generation
- **`VocabularyStoreKit`:** SwiftData models, CloudKit sync
- **`VocabularyUIKit`:** Shared SwiftUI components
- **iOS/macOS apps:** Platform-specific entry points, shared code via packages

### Testing

```bash
swift test                    # All unit tests
swift test VocabularyCoreKitTests  # Specific package
```

Aim for 80%+ code coverage on domain logic.

### Agent Instructions

See [`CLAUDE.md`](CLAUDE.md) for how AI agents should approach development (code style, architecture rules, testing).

## Milestones

| M | Feature | Days | Status |
|---|---------|------|--------|
| 1 | SwiftData models | 2 | Planned |
| 2 | CloudKit sync | 2 | Planned |
| 3 | SM-2 algorithm | 1 | Planned |
| 4 | Manual capture UI | 2 | Planned |
| 5 | Document scanning | 2 | Planned |
| 6 | AI quiz/podcast | 3 | Planned |
| 7 | macOS + polish | 3 | Planned |

See [`MILESTONES.md`](MILESTONES.md) for detailed acceptance criteria.

## Privacy & Data

- **No backend:** All code runs on your device
- **iCloud sync:** Data syncs to your iCloud account (encrypted)
- **API tokens:** Stored in Keychain (encrypted), never logged
- **Sharing:** Optional, user-controlled, revocable

## Requirements

- **Swift:** 6.2+
- **Xcode:** 15+
- **iOS:** 16+ (base features), 18.2+ (on-device AI)
- **macOS:** 13+
- **Apple Developer account:** For iCloud container setup

## License

[Pending]

## Credits

Built with AI agents using Addy Osmani's agentic engineering methodology.
