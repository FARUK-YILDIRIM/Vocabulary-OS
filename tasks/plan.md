# Implementation Plan: Vocabulary-OS v1

## Overview

This plan builds the v1 described in [`SPEC.md`](../SPEC.md). It is ordered for risk: the
riskiest part, on-device "meaning in context", is built and measured right after the
foundation. After that comes one thin end-to-end slice (capture → insight → save → library); later
phases widen it. Each task:
- is one commit, `<type>(<scope>): …`;
- leaves `scripts/verify.sh` green;
- is ticked in [`todo.md`](todo.md).

Each phase ends at a checkpoint, where the human reviews before the next phase starts.

Definition of Done for every task: see [`CLAUDE.md`](../CLAUDE.md#definition-of-done).

## Architecture Decisions

| ADR | Decision |
| --- | --- |
| [001](../docs/ADR-001-apple-only-platform.md) | Apple-only, one multiplatform SwiftUI app, iOS/iPadOS/macOS 26 minimum |
| [002](../docs/ADR-002-cloudkit-private-data-architecture.md) | SwiftData + CloudKit private DB; settings in iCloud KVS; keys in iCloud Keychain; extension inbox; sharing via files |
| [003](../docs/ADR-003-byok-ai-provider-model.md) | On-device Foundation Models by default; curated BYOK cloud providers; `@Generable` outputs shared by all providers |
| [004](../docs/ADR-004-multilingual-architecture.md) | Several learning languages; NaturalLanguage detection with AI tie-break and one-tap override |
| [005](../docs/ADR-005-vision-and-object-capture.md) | Text, `RecognizeDocumentsRequest` pages, `ClassifyImageRequest` objects; thumbnails only |
| [006](../docs/ADR-006-project-structure-and-tooling.md) | XcodeGen, local `VocabularyKit` package, Local/Full entitlements, `scripts/verify.sh` |
| [007](../docs/ADR-007-spaced-repetition-sm2.md) | Classic SM-2 with four ratings, one schedule change per day |
| [008](../docs/ADR-008-podcast-audio-on-device-tts.md) | Podcast = AI script + live on-device TTS; scripts sync, audio doesn't |

## Task List

Sizes: XS = 1 file, S = 1–2 files, M = 3–5 files. The only task over 5 files is T01, the scaffold,
because its files are tiny and only work together.

### Phase 1: Foundation

## Task T01: Scaffold the Xcode project, VocabularyKit package and verify script
- **Description:**
  - Replace the empty first-draft `Package.swift`/`Packages/*Kit` skeleton with the structure from
    ADR-006:
    - `project.yml`, `Config/` (xcconfigs and the two entitlement flavors);
    - a placeholder multiplatform app;
    - `Packages/VocabularyKit` with every module and one smoke test per module;
    - `scripts/verify.sh`;
    - `.gitignore` entries for the generated project and local signing.
- **Acceptance criteria:**
  - [ ] `scripts/verify.sh` runs `xcodegen generate`, `swift test`, an iOS Simulator build and a
    macOS build, and exits 0.
  - [ ] The app launches in the iOS Simulator and on macOS and shows a placeholder screen.
  - [ ] No Team ID or personal identifier is committed; `Config/Signing.local.xcconfig` is ignored
    and `Signing.local.xcconfig.example` documents it.
- **Verification:** run `scripts/verify.sh`; launch the app in the iOS 26.2 Simulator and on the
  Mac; `git status --ignored` shows the generated project as ignored.
- **Dependencies:** none.
- **Files:** `project.yml`, `Config/*`, `App/VocabularyOSApp.swift`, `Packages/VocabularyKit/**`,
  `scripts/verify.sh`, `.gitignore`.
- **Scope:** M (many tiny files).

## Task T02: Language catalog and learner profile (core)
- **Description:** In `VocabularyCore`, add:
  - `LanguageCode` (BCP-47 language subtag);
  - `Language` (code, English name, native name);
  - `LanguageCatalog`, the supported list from SPEC C1/C2;
  - `LearnerProfile`: native language plus ordered learning languages, with add/remove/reorder and
    the validation "native ∉ learning, no duplicates".
- **Acceptance criteria:**
  - [ ] Unit tests cover add, remove, duplicates, the native language as a learning language, and
    unknown codes.
  - [ ] The catalog contains every on-device-supported language observed in ADR-004/ADR-003, with
    autonyms.
- **Verification:** `swift test --filter VocabularyCoreTests`.
- **Dependencies:** T01.
- **Files:** `Sources/VocabularyCore/Language.swift`, `LanguageCatalog.swift`,
  `LearnerProfile.swift`, `Tests/VocabularyCoreTests/LearnerProfileTests.swift`.
- **Scope:** S.

## Task T03: Synced settings store (data)
- **Description:**
  - `SettingsStore` keeps the learner profile, the active AI provider/model, review limits and the
    onboarding flag.
  - It is backed by `NSUbiquitousKeyValueStore` with a `UserDefaults` mirror, and publishes external
    changes (ADR-002).
  - The backing is behind a protocol, so tests use an in-memory fake.
- **Acceptance criteria:**
  - [ ] Values round-trip through the store.
  - [ ] An external change notification updates the observable settings.
  - [ ] No API key can be stored here: the type has no field for it.
- **Verification:** `swift test --filter VocabularyDataTests`.
- **Dependencies:** T02.
- **Files:** `Sources/VocabularyData/SettingsStore.swift`, `KeyValueBacking.swift`,
  `Tests/VocabularyDataTests/SettingsStoreTests.swift`.
- **Scope:** S.

## Task T04: Onboarding and language settings (app)
- **Description:**
  - First-launch onboarding: pick the native language and one or more learning languages.
  - Settings → Languages: add/remove learning languages.
  - An `AppModel` (`@Observable`) owns the dependencies.
- **Acceptance criteria:**
  - [ ] The choices persist across relaunch.
  - [ ] The native language cannot also be chosen as a learning language.
  - [ ] Works on iPhone, iPad and Mac layouts.
- **Verification:** Simulator screenshots (iPhone 17, iPad) and a macOS run; `scripts/verify.sh`.
- **Dependencies:** T03.
- **Files:** `App/AppModel.swift`, `App/Onboarding/OnboardingView.swift`,
  `App/Settings/LanguageSettingsView.swift`, `Sources/VocabularyUI/LanguagePicker.swift`.
- **Scope:** M.

### Checkpoint 1 — Foundation
- [ ] `scripts/verify.sh` green.
- [ ] The app runs on iOS and macOS, and onboarding persists.
- [ ] Human review.

### Phase 2: Meaning in context (highest risk first)

## Task T05: Term selection and sentence context (core)
- **Description:**
  - Tokenize text into selectable word tokens, with punctuation stripped from the term.
  - Support selecting one token or a contiguous span.
  - Extract the sentence containing the selection (`NLTokenizer(unit: .sentence)`, even across line
    breaks).
  - Get the lemma and lexical class through `NLTagger` when the scheme is available.
- **Acceptance criteria:**
  - [ ] Tests pass for English, German and Turkish samples, multi-line paragraphs, and the
    punctuation cases "Bank," and "cookies.".
  - [ ] The lemma is "run" for "ran" and "kitap" for "kitapları"; it is nil for German (scheme
    unavailable).
- **Verification:** `swift test --filter VocabularyCoreTests`.
- **Dependencies:** T02.
- **Files:** `Sources/VocabularyCore/TextSelection.swift`, `SentenceContext.swift`,
  `Tests/VocabularyCoreTests/TextSelectionTests.swift`.
- **Scope:** S.

## Task T06: Language routing (core)
- **Description:** `LanguageRouter` decides `.confident(code)`, `.ambiguous([candidates])` or
  `.notLearning(code)` from text and the profile. It uses `NLLanguageRecognizer` limited to the
  profile's languages and the thresholds in ADR-004.
- **Acceptance criteria:**
  - [ ] A German sentence is confident German.
  - [ ] The single words "Hand"/"Kind" are ambiguous between en and de.
  - [ ] A French sentence for an en/de learner is `notLearning(fr)`.
- **Verification:** `swift test --filter VocabularyCoreTests`.
- **Dependencies:** T02.
- **Files:** `Sources/VocabularyCore/LanguageRouter.swift`,
  `Tests/VocabularyCoreTests/LanguageRouterTests.swift`.
- **Scope:** S.

## Task T07: Generation client contract and Apple on-device client (ai)
- **Description:**
  - `GenerationClient` protocol: typed `@Generable` generation plus a dynamic-schema generation.
  - `AppleOnDeviceClient` over `SystemLanguageModel`/`LanguageModelSession`.
  - `AIError`, mapping availability and `GenerationError` cases to user-facing errors.
- **Acceptance criteria:**
  - [ ] Unit tests cover every availability and error mapping.
  - [ ] An opt-in live test (`VOS_LIVE_MODEL=1`) generates a small `@Generable` value on this Mac.
- **Verification:** `swift test --filter VocabularyAITests`, then
  `VOS_LIVE_MODEL=1 swift test --filter Live`.
- **Dependencies:** T01.
- **Files:** `Sources/VocabularyAI/GenerationClient.swift`, `AppleOnDeviceClient.swift`,
  `AIError.swift`, `Tests/VocabularyAITests/AppleOnDeviceClientTests.swift`.
- **Scope:** S.

## Task T08: Word insight service with validation (ai)
- **Description:**
  - `WordInsight` value type (core).
  - `InsightService` with the on-device three-step flow:
    1. sense: situation, English gloss, lemma, part of speech;
    2. native: translation, meaning, grammar note;
    3. details: examples and other meanings.
  - The prompts use language names injected through `DynamicGenerationSchema` (ADR-003 evidence).
  - Validators check that the translation is a phrase, that native fields are in the native
    language (via `NLLanguageRecognizer`), and that lengths are capped. One retry is allowed on a
    validation failure.
- **Acceptance criteria:**
  - [ ] Tests with a scripted fake client cover success, retry-then-success, and failure after
    retry.
  - [ ] Every field in a returned insight is validated.
- **Verification:** `swift test --filter VocabularyAITests`.
- **Dependencies:** T05, T07.
- **Files:** `Sources/VocabularyCore/WordInsight.swift`, `Sources/VocabularyAI/InsightService.swift`,
  `InsightPrompts.swift`, `InsightValidator.swift`, `Tests/VocabularyAITests/InsightServiceTests.swift`.
- **Scope:** M.

## Task T09: vos-eval prompt evaluation (ai)
- **Description:**
  - The `vos-eval` executable runs the insight fixtures (cookie ×2, Bank ×2, pitch ×2, ran, an
    idiom, abzuheben, Schlüssel) against the on-device model.
  - It reports the right-sense rate, language adherence and latency.
  - Results go in `docs/eval/insight-on-device.md`.
- **Acceptance criteria:**
  - [ ] At least 8 of 10 senses are right and 10 of 10 have valid languages on device. If not,
    iterate the prompts and record each attempt.
  - [ ] Median latency is under 3 s per basic insight.
- **Verification:** `swift run --package-path Packages/VocabularyKit vos-eval insight`.
- **Dependencies:** T08.
- **Files:** `Sources/vos-eval/main.swift`, `Sources/vos-eval/InsightFixtures.swift`,
  `docs/eval/insight-on-device.md`.
- **Scope:** S.

## Task T10: SwiftData schema v1 and word repository (data)
- **Description:**
  - The `VocabularyEntry` and `WordList` models follow the CloudKit rules, inside a
    `VersionedSchema` v1.
  - `WordRepository` creates, updates and deletes words, fetches them by language with filters,
    finds duplicates by lemma and language, and maps to and from core values.
- **Acceptance criteria:**
  - [ ] In-memory tests cover CRUD and list membership; deleting a word nullifies list membership.
  - [ ] A schema rule test asserts there are no unique attributes, every attribute is optional or
    defaulted, and every relationship is optional with an inverse.
- **Verification:** `swift test --filter VocabularyDataTests`.
- **Dependencies:** T03, T08.
- **Files:** `Sources/VocabularyData/Schema/SchemaV1.swift`, `VocabularyEntry.swift`,
  `WordList.swift`, `WordRepository.swift`, `Tests/VocabularyDataTests/WordRepositoryTests.swift`.
- **Scope:** M.

## Task T11: In-app text capture (capture slice)
- **Description:**
  - The capture screen turns pasted or typed text into tappable tokens. The user selects a word or
    span.
  - Language routing appears as a chip.
  - Insight streams into an `InsightCard`, and Save stores the word through `WordRepository`.
- **Acceptance criteria:**
  - [ ] In the Simulator, capturing "cookies" from "This website uses cookies for tracking." with
    the on-device model saves an English word with a Turkish translation.
  - [ ] An ambiguous single word shows the language chip.
- **Verification:** Simulator screenshots of each step; `scripts/verify.sh`.
- **Dependencies:** T04, T06, T09, T10.
- **Files:** `Sources/VocabularyUI/SelectableTextView.swift`, `InsightCard.swift`,
  `App/Capture/CaptureView.swift`, `App/Capture/CaptureModel.swift`.
- **Scope:** M.

## Task T12: Library and word detail
- **Description:**
  - Library: words per learning language with search, filters and sort.
  - Word detail: all fields, the context with the term highlighted, edit, favorite, delete,
    regenerate the insight.
- **Acceptance criteria:**
  - [ ] Saved words appear immediately.
  - [ ] Edits persist.
  - [ ] Delete asks for confirmation.
  - [ ] Works on iPhone, iPad and Mac.
- **Verification:** Simulator and macOS screenshots; `scripts/verify.sh`.
- **Dependencies:** T11.
- **Files:** `App/Library/LibraryView.swift`, `App/Library/WordDetailView.swift`,
  `App/Library/WordEditView.swift`, `Sources/VocabularyUI/HighlightedText.swift`.
- **Scope:** M.

### Checkpoint 2 — Core slice
- [ ] Capture → insight → save → library works on iOS and macOS with the on-device model.
- [ ] The eval results are recorded.
- [ ] Human review.

### Phase 3: Bring-your-own-key providers

## Task T13: Provider catalog and Keychain secret store (ai)
- **Description:**
  - `ProviderCatalog` covers Apple on-device, OpenAI, Anthropic, Google Gemini, DeepSeek,
    OpenRouter, Mistral and a custom OpenAI-compatible endpoint. Each entry has its base URL, key
    page URL, recommended models and capabilities.
  - `KeychainSecretStore` per ADR-002: synchronizable, the App Group access group, the data
    protection keychain on macOS, and a local fallback for unsigned builds.
- **Acceptance criteria:**
  - [ ] Catalog invariant tests: unique IDs, HTTPS base URLs except for local servers, at least one
    recommended model.
  - [ ] Secret store tests run against an in-memory fake, plus a Keychain round trip on the host.
- **Verification:** `swift test --filter VocabularyAITests`.
- **Dependencies:** T07.
- **Files:** `Sources/VocabularyAI/ProviderCatalog.swift`, `SecretStore.swift`,
  `KeychainSecretStore.swift`, `Tests/VocabularyAITests/ProviderCatalogTests.swift`.
- **Scope:** M.

## Task T14: OpenAI-compatible client (ai)
- **Description:**
  - A Chat Completions client with JSON Schema output derived from `GenerationSchema`. It falls back
    to JSON mode where the provider lacks schema support.
  - Replies are parsed through `GeneratedContent(json:)`, tolerating code fences.
  - HTTP errors map to `AIError`.
  - The model list comes from `GET /models`.
- **Acceptance criteria:**
  - [ ] Stubbed tests check the request body and headers for OpenAI, Gemini, DeepSeek, OpenRouter,
    Mistral and a custom endpoint.
  - [ ] Decoding of valid, fenced and malformed replies is tested.
  - [ ] Statuses 401, 403, 402, 429 and 5xx map to the right errors.
- **Verification:** `swift test --filter VocabularyAITests`.
- **Dependencies:** T13.
- **Files:** `Sources/VocabularyAI/OpenAICompatibleClient.swift`, `JSONSchemaAdapter.swift`,
  `HTTPTransport.swift`, `Tests/VocabularyAITests/OpenAICompatibleClientTests.swift`,
  `Tests/VocabularyAITests/StubURLProtocol.swift`.
- **Scope:** M.

## Task T15: Anthropic Messages client (ai)
- **Description:** A Messages API client. Structured output comes from forced tool use (or the
  provider's structured-output feature, per ADR-003). Model listing and error mapping are included.
- **Acceptance criteria:**
  - [ ] Stubbed tests check the request shape: `x-api-key`, `anthropic-version`, the tool schema and
    `tool_choice`.
  - [ ] Tests cover decoding of the tool input and the error statuses.
- **Verification:** `swift test --filter VocabularyAITests`.
- **Dependencies:** T14.
- **Files:** `Sources/VocabularyAI/AnthropicClient.swift`,
  `Tests/VocabularyAITests/AnthropicClientTests.swift`.
- **Scope:** S.

## Task T16: AI provider settings and cloud insight path
- **Description:**
  - Settings → AI: on-device status, a provider list, key entry, a model picker (recommended plus
    fetched) and Test connection.
  - A privacy notice appears before the first cloud request.
  - `InsightService` uses the single-call full schema when the active provider is a cloud provider.
- **Acceptance criteria:**
  - [ ] Switching providers changes the client used (unit test).
  - [ ] An invalid key shows "Invalid API key".
  - [ ] Keys never appear in the settings store (test).
- **Verification:** Simulator screenshots; `scripts/verify.sh`.
- **Dependencies:** T12, T15.
- **Files:** `App/Settings/AISettingsView.swift`, `App/Settings/ProviderDetailView.swift`,
  `Sources/VocabularyAI/ProviderRouter.swift`, `Tests/VocabularyAITests/ProviderRouterTests.swift`.
- **Scope:** M.

### Checkpoint 3 — Providers
- [ ] On-device and at least one cloud provider (tested manually by the maintainer) work end to end.
- [ ] Human review.

### Phase 4: Capture everywhere

## Task T17: Share extension inbox (data + iOS extension)
- **Description:**
  - `CaptureInbox` writes and reads JSON drafts in the App Group container.
  - The iOS Share extension hosts the shared capture UI and saves to the inbox.
  - The app imports the inbox whenever it becomes active.
- **Acceptance criteria:**
  - [ ] Inbox tests: write, import, delete, and a corrupt file is skipped and logged.
  - [ ] In the Simulator, sharing text from Notes and saving makes the word appear in the app.
- **Verification:** `swift test`; a Simulator walkthrough.
- **Dependencies:** T16.
- **Files:** `Sources/VocabularyData/CaptureInbox.swift`,
  `Tests/VocabularyDataTests/CaptureInboxTests.swift`,
  `Extensions/ShareExtension/ShareViewController.swift`, `project.yml`.
- **Scope:** M.

## Task T18: macOS Share extension and Services menu
- **Description:**
  - The Share extension on macOS.
  - A Services provider ("Capture in Vocabulary-OS") opens quick capture with the selected text.
- **Acceptance criteria:**
  - [ ] On macOS, selected text → Services → the capture window opens with the text.
  - [ ] Sharing from Safari saves to the inbox (signed build).
- **Verification:** a macOS run; `scripts/verify.sh`.
- **Dependencies:** T17.
- **Files:** `App/Platform/ServicesProvider.swift`, `App/Info.plist` entries via `project.yml`,
  `Extensions/ShareExtension/*`.
- **Scope:** M.

## Task T19: Page text recognition (capture)
- **Description:**
  - `PageTextRecognizer` (`RecognizeDocumentsRequest`) produces a `PageText` model: paragraphs,
    words with normalized boxes, and the sentence for a word.
  - `ImageThumbnailer` (ImageIO) limits the long edge to 1024 px, at JPEG quality 0.7.
- **Acceptance criteria:**
  - [ ] Generated page images in German and English return the right sentence for a word that wraps
    across lines.
  - [ ] Thumbnails are at most 1024 px.
- **Verification:** `swift test --filter VocabularyCaptureTests`.
- **Dependencies:** T05.
- **Files:** `Sources/VocabularyCapture/PageTextRecognizer.swift`, `PageText.swift`,
  `ImageThumbnailer.swift`, `Tests/VocabularyCaptureTests/PageTextRecognizerTests.swift`.
- **Scope:** M.

## Task T20: Page capture screen
- **Description:**
  - The learner picks a photo or takes one (iOS camera).
  - The image shows tappable word boxes; a tap goes into the capture flow, with an optional page
    thumbnail.
- **Acceptance criteria:**
  - [ ] In the Simulator with a sample page image, tapping a word opens capture with its full
    sentence.
  - [ ] Works on macOS with a file picker.
- **Verification:** Simulator and macOS screenshots.
- **Dependencies:** T11, T19.
- **Files:** `App/Capture/PageCaptureView.swift`, `Sources/VocabularyUI/WordOverlayView.swift`,
  `App/Capture/CameraPicker.swift`.
- **Scope:** M.

## Task T21: Object capture
- **Description:**
  - `ObjectClassifier` (`ClassifyImageRequest`) returns the top labels.
  - The `ObjectNaming` prompt returns the term in the learning language with an article, a native
    translation and an example.
  - UI: photo → pick or correct the label → save with the photo.
- **Acceptance criteria:**
  - [ ] Classifier tests on a bundled sample photo.
  - [ ] Naming validator tests.
  - [ ] Simulator walkthrough saves "die Tasse" (de) for a cup photo with the on-device model.
- **Verification:** `swift test`; Simulator screenshots.
- **Dependencies:** T20.
- **Files:** `Sources/VocabularyCapture/ObjectClassifier.swift`,
  `Sources/VocabularyAI/ObjectNamingService.swift`, `App/Capture/ObjectCaptureView.swift`,
  `Tests/VocabularyCaptureTests/ObjectClassifierTests.swift`.
- **Scope:** M.

### Checkpoint 4 — Capture
- [ ] Text, share sheet, Services, page and object capture all save words.
- [ ] Human review.

### Phase 5: Practice

## Task T22: SM-2 scheduler and daily queue (core)
- **Description:**
  - `ReviewScheduler` per ADR-007.
  - `DailyQueue`: new and review limits, at most one schedule change per day, in-session re-queue.
- **Acceptance criteria:**
  - [ ] Table-driven tests for rating sequences, lapses, the ease floor, rounding and
    midnight/time-zone boundaries.
- **Verification:** `swift test --filter VocabularyCoreTests`.
- **Dependencies:** T02.
- **Files:** `Sources/VocabularyCore/ReviewScheduler.swift`, `CardState.swift`, `DailyQueue.swift`,
  `Tests/VocabularyCoreTests/ReviewSchedulerTests.swift`.
- **Scope:** M.

## Task T23: Flashcard review and Today screen
- **Description:**
  - The `ReviewLog` model and review persistence in the repository.
  - Today shows due and new counts per language.
  - A flashcard session with reveal and four ratings.
- **Acceptance criteria:**
  - [ ] Reviewing updates the due date and writes a log (test).
  - [ ] Today counts match the repository (test).
  - [ ] The session works in the Simulator.
- **Verification:** `swift test`; Simulator screenshots.
- **Dependencies:** T12, T22.
- **Files:** `Sources/VocabularyData/ReviewLog.swift`, `ReviewRepository.swift`,
  `App/Today/TodayView.swift`, `App/Review/FlashcardSessionView.swift`.
- **Scope:** M.

## Task T24: Quiz generation and validation (ai)
- **Description:**
  - A `QuizQuestion` `@Generable` covering meaning, reverse, cloze and listening.
  - `QuizService` generates one question per call on device and in batches on cloud models.
  - The validator requires four distinct options, exactly one correct, and the cloze target present.
  - A local fallback generator builds questions from saved data.
- **Acceptance criteria:**
  - [ ] Validator tests reject each malformed case.
  - [ ] Fallback generation always produces valid questions.
  - [ ] Live eval: 10 on-device questions are valid.
- **Verification:** `swift test --filter VocabularyAITests`; `vos-eval quiz`.
- **Dependencies:** T08, T22.
- **Files:** `Sources/VocabularyAI/QuizService.swift`, `QuizPrompts.swift`,
  `Sources/VocabularyCore/QuizValidator.swift`, `Tests/VocabularyAITests/QuizServiceTests.swift`.
- **Scope:** M.

## Task T25: Quiz session and grading
- **Description:**
  - Quiz setup: language, word source and length.
  - The session streams questions, gives immediate feedback and ends with a summary.
  - Grading writes review logs through the scheduler.
- **Acceptance criteria:**
  - [ ] The first question appears in under 5 s on device.
  - [ ] Answers update review state with the once-per-day rule (test).
- **Verification:** `swift test`; Simulator screenshots.
- **Dependencies:** T23, T24.
- **Files:** `App/Practice/QuizSetupView.swift`, `App/Practice/QuizSessionView.swift`,
  `App/Practice/QuizSessionModel.swift`, `Sources/VocabularyData/QuizRecord.swift`.
- **Scope:** M.

## Task T26: Speech engine (speech)
- **Description:**
  - `VoiceCatalog` picks the best installed voice per language and two distinct voices for
    dialogues.
  - `SpeechPlayer` plays segments with speed control.
  - Word detail gets a "listen" button.
- **Acceptance criteria:**
  - [ ] Voice selection tests use injected voice lists.
  - [ ] "listen" speaks the term in its language on macOS and in the Simulator.
- **Verification:** `swift test --filter VocabularySpeechTests`; a manual listen check.
- **Dependencies:** T12.
- **Files:** `Sources/VocabularySpeech/VoiceCatalog.swift`, `SpeechPlayer.swift`,
  `Tests/VocabularySpeechTests/VoiceCatalogTests.swift`, `App/Library/WordDetailView.swift`.
- **Scope:** M.

## Task T27: Podcast script generation (ai + data)
- **Description:**
  - A `PodcastScript` `@Generable` holds a title, segments and a glossary.
  - `PodcastService` generates in sections on device and in one call in the cloud.
  - The validator checks that every target word or inflection is present and that lengths are
    capped.
  - Episodes are stored as `PodcastEpisode` models.
- **Acceptance criteria:**
  - [ ] Validator tests, including inflections such as "ran" for "run" and "Banken" for "Bank".
  - [ ] Live eval: an on-device two-minute script contains all words.
- **Verification:** `swift test`; `vos-eval podcast`.
- **Dependencies:** T24.
- **Files:** `Sources/VocabularyAI/PodcastService.swift`, `PodcastPrompts.swift`,
  `Sources/VocabularyCore/PodcastValidator.swift`, `Sources/VocabularyData/PodcastEpisode.swift`.
- **Scope:** M.

## Task T28: Podcast setup and player
- **Description:**
  - Setup: language, words, level, length and style.
  - An episode list.
  - A player with transcript highlighting, word links and speed control.
- **Acceptance criteria:**
  - [x] An episode generated in the Simulator plays through.
  - [x] Tapping a highlighted word opens its detail.
  - [x] Works on macOS.
- **Verification:** Simulator and macOS walkthrough.
- **Dependencies:** T26, T27.
- **Files:** `App/Practice/PodcastSetupView.swift`, `App/Practice/PodcastPlayerView.swift`,
  `App/Practice/PodcastListView.swift`.
- **Scope:** M.

### Checkpoint 5 — Practice
- [ ] Review, quiz and podcast loops work on device AI.
- [ ] Human review.

### Phase 6: Plans, sharing, polish

## Task T29: Study plans and notifications
- **Description:**
  - The `StudyPlan` model and a plans UI.
  - `NotificationScheduler` reconciles pending requests with the plans: weekly
    `UNCalendarNotificationTrigger`s, at most 64.
  - Deep links (`vocabularyos://plan/<id>`) start the activity.
- **Acceptance criteria:**
  - [x] Scheduler tests: Mon/Wed/Fri 08:00 gives three triggers; editing or deleting reconciles;
    the cap is enforced.
  - [x] Tapping the notification opens the activity (Simulator).
- **Verification:** `swift test`; a Simulator notification check.
- **Dependencies:** T25, T28.
- **Files:** `Sources/VocabularyData/StudyPlan.swift`, `Sources/VocabularyCore/PlanSchedule.swift`,
  `App/Plans/PlansView.swift`, `App/Plans/NotificationScheduler.swift`.
- **Scope:** M.

## Task T30: Export and import
- **Description:**
  - A versioned `.vocabularyos` document (`UTType` export), `ShareLink` export of a list or a
    language, and import with de-duplication.
  - CSV export.
- **Acceptance criteria:**
  - [ ] Round-trip and duplicate tests.
  - [ ] Keys and review logs are never exported (test).
  - [ ] Opening a file in the app imports it.
- **Verification:** `swift test`; Simulator walkthrough.
- **Dependencies:** T12.
- **Files:** `Sources/VocabularyData/WordListDocument.swift`, `CSVExporter.swift`,
  `Tests/VocabularyDataTests/ExportImportTests.swift`, `App/Library/ExportImport.swift`.
- **Scope:** M.

## Task T31: Turkish localization
- **Description:** Every UI string is translated in the String Catalog, with pluralization where
  needed.
- **Acceptance criteria:**
  - [ ] No untranslated key for `tr`.
  - [ ] Simulator screenshots in Turkish.
- **Verification:** an `xcodebuild` string-catalog build with no missing-translation warnings for
  `tr`.
- **Dependencies:** T29, T30.
- **Files:** `App/Resources/Localizable.xcstrings`, plus extension strings.
- **Scope:** S.

## Task T32: Accessibility and polish
- **Description:** VoiceOver labels and traits, Dynamic Type checks, empty and error states, and
  the app icon.
- **Acceptance criteria:**
  - [ ] An Accessibility Inspector audit has no errors on the main screens.
  - [ ] The largest Dynamic Type size is usable.
- **Verification:** Simulator audit screenshots.
- **Dependencies:** T31.
- **Files:** views touched as needed; `App/Resources/Assets.xcassets`.
- **Scope:** M.

## Task T33: Open-source release readiness
- **Description:**
  - The README covers features, screenshots, build and signing setup, privacy and the
    architecture.
  - Add the LICENSE (owner's choice), CONTRIBUTING.md and SECURITY.md.
  - The ship review runs three reviews (code, security, tests) and records a GO/NO-GO decision.
- **Acceptance criteria:**
  - [ ] A fresh clone builds following the README alone.
  - [ ] The ship review has no Critical findings open.
- **Verification:** follow the README in a clean checkout; `scripts/verify.sh`.
- **Dependencies:** T32.
- **Files:** `README.md`, `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`, `docs/ship-review.md`.
- **Scope:** S.

### Checkpoint 6 — Ship
- [ ] Success criteria 1–13 in SPEC.md checked.
- [ ] Human GO.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| The on-device model picks the wrong sense or answers in the wrong language (it is "not designed for world knowledge"; seen in early probes) | High | Small multi-step prompts with language names in the schema, validators with one retry, `vos-eval` before and after every prompt change, a clear "connect a cloud model for better results" path |
| A CloudKit schema mistake only shows up with real sync | High | Model-rule test (T10), additive-only changes, a manual two-device sync test with a signed build before release |
| Foundation Models unavailable or too heavy inside the Share extension | Medium | The extension can save term + sentence without insight; the app fills in the insight on import |
| Unsigned contributor builds can't use App Groups or keychain sharing on macOS | Medium | `Local` entitlement flavor with fallbacks (ADR-006); documented in the README |
| The Simulator has no camera | Low | Photo-picker path plus sample images; camera is checked on a device by the maintainer |
| Provider APIs or model IDs change | Medium | Live model listing, a free-form model ID, a central catalog |
| 64 pending notifications per app | Low | Weekly repeating triggers, a cap enforced in the scheduler |
| Scope is large for v1 | Medium | v1.1 list in the spec, checkpoints after each phase |

## Open Questions

See [SPEC.md → Open Questions](../SPEC.md#open-questions). Questions 1 (signing identity) and 2
(license) block only T33 and real-device sync. Question 3 (photos to cloud) affects T21.
