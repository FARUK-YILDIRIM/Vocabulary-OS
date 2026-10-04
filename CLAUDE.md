# Project: Vocabulary-OS

Open-source vocabulary app for iPhone, iPad and Mac. Learners capture words in context (text, book
pages, objects), get the meaning in their native language from on-device or bring-your-own-key AI,
and reinforce the words with spaced review, quizzes and podcasts. There is no server: data stays in
the user's private iCloud.

Read before working:
- [`SPEC.md`](SPEC.md): what we build and how success is measured.
- [`docs/`](docs): ADRs, the decisions and their reasons.
- [`tasks/plan.md`](tasks/plan.md) and [`tasks/todo.md`](tasks/todo.md): the task list and progress.

## Workflow

This project follows the agent-skills lifecycle (https://skills.addy.ie): spec → plan → build →
verify → review → ship.

For each task:
1. Take the next unchecked task in `tasks/todo.md` and read its acceptance criteria in
   `tasks/plan.md`.
2. Load only the files the task needs.
3. Write the failing test first, where the behavior is testable.
4. Implement the minimum that makes it pass, keeping the build green.
5. Run `scripts/verify.sh`.
6. Commit with a Conventional Commit message (below) and tick the task in `tasks/todo.md`.

Rules while working:
- Stay in scope. If you notice something unrelated, record it under "Noticed, not touched" in the
  commit body. Do not fix it on the side.
- If the spec is ambiguous or two sources disagree, stop and write a `CONFUSION:` note with the
  options instead of guessing.
- Check every Apple API against the SDK interface or developer.apple.com before using it
  (source-driven). Never rely on memory for API names or OS versions. Cite sources in ADRs.

## Tech Stack

- Swift 6.2, Swift 6 language mode; Xcode 26.2 or newer; XcodeGen 2.46.
- iOS / iPadOS / macOS 26 minimum; one multiplatform SwiftUI app target plus a Share extension.
- SwiftData + CloudKit (private DB), `NSUbiquitousKeyValueStore`, Keychain (iCloud Keychain).
- FoundationModels (on-device AI); `URLSession` clients for cloud providers (no SDKs).
- Vision, NaturalLanguage, AVFoundation, UserNotifications.
- Swift Testing; XCTest only for UI tests. No third-party runtime dependencies.

## Commands

```bash
xcodegen generate                                   # regenerate VocabularyOS.xcodeproj (never edit it by hand)
swift test --package-path Packages/VocabularyKit    # package tests on the Mac host
scripts/verify.sh                                   # full gate: generate + tests + iOS Simulator + macOS builds
scripts/ui-test.sh [Class/test]                     # XCUITests on iPhone 17 (VOS_UI_TEST_DEVICE for iPad); screenshots in .build/ui-tests
scripts/mac-smoke.sh [-vos-preset-profile tr:en,de] # macOS Debug build launches, shows a window, logs no errors
scripts/mac-smoke.sh --self-test [capture|page|object|quiz|speech]  # the macOS app with the real model and voices
scripts/mac-smoke.sh --services                     # Services → "Capture in Vocabulary-OS" opens the capture window
swift run --package-path Packages/VocabularyKit vos-eval insight|quiz|podcast [--verbose]   # live on-device prompt evaluation
```

## Code Conventions

- **Concurrency:** the app target and `VocabularyUI` default to `MainActor` isolation. Other modules
  are non-isolated and use `Sendable` value types or actors. Use `async`/`await` only, never Dispatch.
- **State and dependencies:** `@Observable` for UI state; never `ObservableObject`. Inject
  dependencies through initializers or protocols; no global singletons of our own.
- **Errors:** typed enums conforming to `LocalizedError`, with user-facing messages. No force
  unwraps or `try!` outside tests.
- **Logging:** `Logger(subsystem: "app.vocabularyos", category: "<module>")`. Mark user text
  `privacy: .private`. Never log API keys, not even partially.
- **Style:**
  - Comments explain *why*; give public API a one-line doc comment.
  - Follow the Swift API Design Guidelines; name each file after its main type.
- **Localization:** UI strings are `LocalizedStringKey`/`String(localized:)` and live in the String
  Catalog. Do not concatenate localized fragments.

## Boundaries

- **Always:**
  - Run `scripts/verify.sh` before committing.
  - Keep SwiftData models CloudKit-compatible: no `.unique`, every property optional or defaulted,
    relationships optional with an inverse.
  - Keep `SPEC.md` and the ADRs current.
- **Ask first:**
  - A new dependency.
  - Schema changes after v1 ships.
  - A new AI provider, or sending a new kind of data to providers.
  - Changing the minimum OS.
  - Signing, entitlements, bundle IDs or CloudKit containers.
  - Rewriting git history.
- **Never:**
  - Add a server, analytics or tracking.
  - Store API keys outside the Keychain.
  - Commit secrets, Team IDs or personal data.
  - Skip or delete failing tests.
  - Edit the generated `.xcodeproj`.

## Patterns

- **Module dependencies:** `VocabularyCore` ← `VocabularyAI` / `VocabularyData` /
  `VocabularyCapture` / `VocabularySpeech` ← `VocabularyUI` ← App and Share extension.
  - `VocabularyCore` imports only Foundation and NaturalLanguage.
  - Only `VocabularyUI` and the app import SwiftUI.
- **SwiftData models** live in `VocabularyData`. Use `var id: UUID = UUID()` for identity and give
  every stored property a default. Domain logic works on value types from `VocabularyCore`
  (`CardState`, `WordInsight`, …), not on `@Model` classes.
- **AI outputs** are `@Generable` structs in `VocabularyAI`:
  - The on-device client uses guided generation.
  - Cloud clients send the JSON Schema encoded from `GenerationSchema` and parse replies with
    `GeneratedContent(json:)`.
  - Every output passes a validator before it reaches the UI or the store.
  - On-device prompts stay small: one task per call, about 1–3 short paragraphs, and an explicit
    `maximumResponseTokens`. Do not use regex guides; they fail on device.
- **Share extension:**
  - It writes JSON drafts to the App Group `Inbox/`, never to the synced store. The app imports them
    when it becomes active.
  - It reads settings from the App Group mirror and never writes them.
  - It can't receive launch arguments. In Debug builds the app hands it `-vos-ai-stub` and the UI-test
    profile through `ShareExtensionTestHooks` in the App Group defaults.
  - The Simulator has no Notes app, so `ShareExtensionUITests` shares text from Reminders.
  - On the Mac it needs a signed build: unsigned builds have no App Group (`AppGroup` checks the
    entitlement first, because touching an unauthorized group container prompts the user). The
    Services menu (`ServicesProvider`) runs in the app and works in every build.
- **Launch options:** UI tests pass `-key value` pairs, read through `LaunchOptions` from the
  `UserDefaults` argument domain:
  - `-ui-testing YES`: in-memory state.
  - `-vos-preset-profile tr:en,de`: skip onboarding.
  - `-vos-tab settings`: start on that tab.
  - `-vos-ai-stub YES`: canned AI answers (the Simulator has no on-device model assets).
  - `-vos-capture-mode page`: open Capture on the page tab.
  - `-vos-sample-page YES`: load a generated book page (the Simulator has no photos).
  - `-vos-capture-mode object` with `-vos-sample-object YES`: a stand-in cup photo. The Simulator
    can't run Vision's image classifier, so there the learner types the label.

  Never pass a bare flag: AppKit then treats the next value as a file to open.
- **Tests:**
  - Use Swift Testing (`@Test`, `#expect`).
  - SwiftData tests use `ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)`.
  - HTTP is stubbed with a `URLProtocol` subclass; tests never touch the network.
  - After changing a public enum, an incremental `swift test` can link stale code and compare enum
    values wrongly. Run `swift package clean` before chasing such failures.

## Definition of Done

A task is done only when all of these hold:
- Its acceptance criteria are met, and new behavior has tests that failed before the change.
- `scripts/verify.sh` passes with no new warnings in project code.
- UI tasks were checked in the iOS Simulator with `scripts/ui-test.sh` on iPhone and iPad, and on
  macOS with `scripts/mac-smoke.sh`. Screenshots were reviewed. Visual checks of macOS screens happen
  at checkpoints with the owner.
- Docs, the spec and the ADRs reflect any decision that changed.
- `tasks/todo.md` is ticked.
- The commit message is in English and follows the convention below.

## Git

- Format: `<type>(<scope>): <imperative summary>` on one line, a body explaining *why*, and the
  trailer `Co-Authored-By: <agent> <noreply@anthropic.com>` when an agent wrote the change.
- **Types:** feat, fix, refactor, test, docs, chore, build, ci.
- **Scopes:** spec, adr, plan, agents, project, core, ai, data, capture, speech, ui, app, share,
  review, quiz, podcast, plans, sharing, i18n, release.
- Make one commit per task. Stage files explicitly (never a blind `git add -A`), then review the
  staged diff for secrets before committing.
