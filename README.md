# Vocabulary-OS

Learn words where you meet them. Vocabulary-OS is a free, open-source vocabulary app for iPhone, iPad
and Mac. Capture a word from a sentence in any app, a page of a paper book or an object in front of
you, and see what it means **in that sentence**, explained in your native language. Then review it
with spaced repetition, AI-generated quizzes and AI-generated podcasts, on a schedule you plan.

- **No server.** Your words live in your private iCloud and sync across your devices.
- **Your choice of AI.** Apple's on-device model works by default, with no key. You can also connect
  OpenAI, Anthropic, Google Gemini, DeepSeek, OpenRouter, Mistral or a local model with your own API
  key.
- **Several languages at once.** Learning English and German at the same time? Words are routed to
  the right language automatically.

> **Status: early development.** The specification and plan are complete, and implementation is
> following [`tasks/todo.md`](tasks/todo.md).

## Requirements

- A Mac with macOS 26 and Xcode 26.2 or newer.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46 or newer: `brew install xcodegen`.
- To run the app: iOS 26, iPadOS 26 or macOS 26. The on-device AI also needs a device with Apple
  Intelligence turned on; otherwise, connect a cloud provider with your own key.

## Getting started

```bash
git clone <this repository>
cd Vocabulary-OS
xcodegen generate          # creates VocabularyOS.xcodeproj from project.yml
open VocabularyOS.xcodeproj
```

Run the **VocabularyOS** scheme on an iPhone/iPad simulator or on "My Mac".

Without any setup, the app is ad-hoc signed and keeps data on the device only. To enable iCloud sync,
the App Group and keychain sharing, build with your own Apple Developer Team:

```bash
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig   # gitignored
# edit the copy: your Team ID and a bundle ID prefix you own
xcodegen generate
```

## Development

```bash
scripts/verify.sh                                  # the gate before every commit
swift test --package-path Packages/VocabularyKit   # package tests only
```

`scripts/verify.sh` regenerates the project, runs the package tests and builds the app for the iOS
Simulator and macOS. It fails on any error or on a compiler warning in project code.

| Path | Contents |
| --- | --- |
| `App/` | The multiplatform SwiftUI app |
| `Packages/VocabularyKit/` | Core logic, AI providers, data, capture, speech and shared UI, each with tests |
| `Config/` | Build settings and entitlements (Local and Full flavors) |
| `docs/` | Architecture decision records |
| `tasks/` | The implementation plan and progress |

Read [`SPEC.md`](SPEC.md) for what the app does and [`docs/`](docs) for why it is built this way.
[`CLAUDE.md`](CLAUDE.md) holds the rules the AI coding agents follow; human contributors follow the
same ones.

## Privacy

- No analytics, telemetry or tracking.
- Network requests go only to the AI provider you configure, and only when you use an AI feature.
- API keys are stored in your Keychain and never leave it, except in requests to their own provider.

## License

To be decided before the first release (see the open questions in [`SPEC.md`](SPEC.md)).
