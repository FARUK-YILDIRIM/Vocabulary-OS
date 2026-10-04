# Spec: Vocabulary-OS

> Status: **Draft for review** (2026-10-04). Architectural decisions live in [`docs/`](docs) as ADRs.
> Replaces the first draft of this file, which contained platform facts that turned out to be wrong
> (for example "Foundation Models on iOS 18.2"). Every Apple API named here was checked against the
> iOS/macOS 26.2 SDK interfaces or run on a Mac with macOS 26.5.

## Objective

Vocabulary-OS is a free, open-source vocabulary app for **iPhone, iPad and Mac**. A learner captures
an unknown word where they meet it — a sentence in any app, a page of a paper book, an object in the
room — and immediately sees what the word means **in that sentence**, explained in their native
language. Saved words are then reinforced with spaced review, AI-generated quizzes and AI-generated
podcasts, on a schedule the learner plans.

There is **no server**. Words, lists, plans and generated content live in the learner's private
iCloud database and sync across their devices. AI runs either **on device** (Apple Foundation
Models, the default, no key needed) or through a provider the learner connects with **their own API
key**.

**Who it is for:** language learners, including people learning several languages at once (for
example a Turkish speaker learning English and German). Words are routed to the right language
automatically.

### Capability map

Each capability can be built and tested on its own. Build order goes top to bottom.

| ID | Capability | Responsibility | Depends on |
| --- | --- | --- | --- |
| C1 | Profile | Native language, learning languages (can be added later), synced settings | — |
| C2 | AI providers | Provider/model catalog, API keys in Keychain, structured generation on device and in the cloud | C1 |
| C3 | Insight | Meaning in context, translation, lemma, examples for a selected term; language detection and routing | C1, C2 |
| C4 | Library | Saved words in SwiftData + CloudKit, lists, search and filters, word detail, edit, delete | C1, C3 |
| C5 | Text capture | In-app capture, Share extension (iOS, iPadOS, macOS), macOS Services menu | C3, C4 |
| C6 | Camera capture | Book page photo → tap a word; object photo → name of the object | C3, C4 |
| C7 | Review | SM-2 spaced repetition, flashcards, Today screen | C4 |
| C8 | Quiz | AI-generated quizzes from chosen words; answers feed review | C2, C4, C7 |
| C9 | Podcast | AI-generated episode script played with on-device text-to-speech | C2, C4 |
| C10 | Plans | Recurring study sessions, local notifications, deep links | C7, C8, C9 |
| C11 | Sharing | Export/import word lists as files, CSV export | C4 |

### User stories and acceptance criteria

**C1 — Profile**
- During onboarding I pick my native language and one or more learning languages. I can add or
  remove learning languages later in Settings.
- Removing a learning language hides its words; adding it back shows them again (nothing is deleted).
- Language settings follow me to my other devices.
- *Accept when:* native `tr` + learning `en`, `de` survive relaunch; the settings store is the iCloud
  key-value store with a local fallback; unit tests cover add/remove/duplicate handling.

**C2 — AI providers**
- By default the app uses the Apple on-device model, with no key and no account. Settings shows its
  status: available, Apple Intelligence turned off, device not eligible, or model still downloading.
- I can connect a cloud provider from a list we maintain: OpenAI, Anthropic, Google Gemini,
  DeepSeek, OpenRouter, Mistral, or any OpenAI-compatible endpoint such as Ollama or LM Studio on a
  Mac. Each entry links to the page where I create a key, offers recommended models, can refresh the
  model list from the provider, and has a "Test connection" button.
- Keys are stored only in the Keychain, synced through iCloud Keychain, and never written to logs,
  UserDefaults, SwiftData or exported files.
- One provider and model is active at a time. If a cloud call fails I see an actionable message
  (invalid key, quota, network) and can retry or switch to the on-device model. There is no silent
  fallback.
- Before the first cloud request I am told what is sent: the selected term, its sentence, and my
  language names.
- *Accept when:*
  - with no key, insight works on device;
  - with a key, requests go to the chosen provider (stubbed-network tests check the request shape
    for every provider family);
  - an invalid key surfaces as "invalid API key";
  - a test asserts the key never appears in the settings store or logs.

**C3 — Insight (meaning in context)**
- Input:
  - the term (a word or a phrase);
  - the sentence it came from (optional);
  - my native language;
  - my learning languages.
- Language routing:
  - The sentence language is detected on device (NaturalLanguage, limited to my languages).
  - A lone word without a sentence is often ambiguous ("Hand" is English or German), so the app
    shows its best guess as a chip I can change. The model breaks ties.
  - If the language is not one I'm learning, the app offers to add it.
- Output, stored with the word:
  - lemma (dictionary form);
  - part of speech;
  - translation into my native language (1–4 words);
  - meaning in this sentence (one sentence, in my native language);
  - an optional grammar note (for example the article and plural of a German noun);
  - two example sentences with translations;
  - up to three other common meanings.
- The basic fields arrive first. Examples and other meanings can load afterwards. This is required
  for the on-device model, which has a 4,096-token context and works best on small, focused prompts.
- *Accept when:*
  - every generated field passes validation: non-empty, the translation is a phrase and not a
    sentence, lengths are capped, and the requested language is used;
  - the evaluation fixtures (`cookies` on a website vs. `cookie` in milk, `Bank` in a park vs. at a
    bank, `pitch` to investors vs. a football pitch, idioms) pick the right sense on device in at
    least 8 of 10 cases, and in 10 of 10 with a cloud model;
  - basic insight on device returns in under 3 s on Apple-silicon hardware.

**C4 — Library**
- Words are grouped by learning language. I can search and filter (new, due, favorites, mastered)
  and sort (recent, A–Z, next review).
- Word detail shows:
  - term, lemma, translation and meaning;
  - the context sentence with the term highlighted;
  - examples and other meanings;
  - the photo, if any;
  - the source;
  - review statistics.
- Word actions: edit any field, favorite, add to a list, regenerate the insight, listen (TTS),
  delete.
- I can create named lists within a language, from the Library's Lists or from a word's page, and
  delete a list without losing its words.
- Saving a word whose lemma already exists in that language offers to open the existing word
  instead.
- Everything works offline and syncs through my private iCloud database when online.
- *Accept when:* create/edit/delete/relationship tests pass on an in-memory SwiftData store; the
  schema follows the CloudKit rules (no unique constraints, every property optional or defaulted,
  optional relationships with inverses).

**C5 — Text capture**
- In the app, I paste or type text. It becomes tappable words. I tap one word, or drag across
  several for a phrase. The sentence around the selection becomes the context automatically.
- From any app's share sheet (Safari, Notes, Books excerpts, Mail …) on iPhone, iPad and Mac, I share
  selected text. The same capture UI runs inside the share extension, and I can save from there.
- On a Mac I can also select text anywhere and use **Services → Capture in Vocabulary-OS**.
- *Accept when:* sharing "This website uses cookies for tracking." and tapping "cookies" saves an
  English word with a Turkish translation and meaning. It appears in the app's library the next time
  the app is active.

**C6 — Camera capture**
- **Book page:**
  - I take a photo (iPhone/iPad camera) or choose an image (Photos, Files, or Finder on Mac).
  - The recognized text appears over the image as tappable words.
  - Tapping a word uses its sentence as context, even when the sentence wraps across lines.
  - Keeping a downscaled page thumbnail with the word is optional.
- **Object:**
  - I take or choose a photo. On-device classification suggests what the object is, and I pick or
    correct the suggestion.
  - The AI gives the object's name in my learning language (with article/gender where the language
    has one), a translation and a one-line meaning in my native language, and an example sentence.
  - If the suggestion fails, I type what the object is, in any language.
  - The word is saved with a downscaled photo.
- *Accept when:* recognition tests on generated page images return the right sentence for a tapped
  word; classification labels map to saved words; photos are stored at most 1024 px on the long edge.

**C7 — Review (spaced repetition)**
- Saved words enter the review queue.
- The Today screen shows how many words are due in each language, plus today's planned sessions.
- Flashcards show the term with its context. I reveal the answer and rate it Again, Hard, Good or
  Easy. SM-2 schedules the next review (ADR-007).
- Daily limits for new words and reviews are configurable.
- *Accept when:* scheduler unit tests cover rating sequences, lapses, ease bounds and day
  boundaries in the user's time zone; reviewing a card persists a review log and the new due date.

**C8 — Quiz**
- Quizzes start from the Practice tab. A language needs at least four saved words, because wrong
  answers come from my other words.
- I choose:
  - a language;
  - the words: due, recent, favorites, a list, or all;
  - a length: 5, 10 or 20 questions.
- The AI writes the questions. Question types:
  - meaning (multiple choice in my native language);
  - reverse (native → term);
  - cloze (a new sentence with a blank);
  - listening (the term is spoken, I pick its meaning).
- The right answer always comes from my saved word. The AI writes a new sentence for every cloze
  question. Wrong answers come from my other saved words when there are at least three, because
  the on-device model's distractors were sometimes synonyms of the answer or in the wrong language
  (`docs/eval/quiz-on-device.md`); with fewer words the AI writes them too.
- Every question is validated: four distinct options, exactly one correct, and the target word
  present where required. If generation fails, a local generator builds questions from my saved
  data.
- Each answer is recorded as a review: correct → Good, wrong → Again. The summary shows what to
  repeat.
- *Accept when:*
  - a 10-question on-device quiz shows its first question in under 5 s;
  - validation rejects malformed questions (tests);
  - grading updates the review state.

**C9 — Podcast**
- I choose:
  - a language;
  - 3–12 words;
  - a level (A1–C2);
  - a length: about 2 or about 5 minutes;
  - a style: a dialogue between two hosts, or a story.
- The AI writes a script that uses every chosen word naturally.
- The player:
  - speaks the script with on-device voices, using two voices for dialogues;
  - has play/pause, previous/next segment and speed controls;
  - shows a transcript where the target words are highlighted and open their word detail;
  - continues where I stopped, and keeps playing on iPhone and iPad while the screen is locked.
- Episodes are listed newest first, and I can delete them.
- Scripts sync. Audio is spoken on each device and never uploaded (ADR-008).
- *Accept when:* validation confirms each chosen word (or an inflected form) appears in the script;
  playback works on the iOS simulator and on macOS; a missing voice falls back to the default voice
  for the language, with a notice.

**C10 — Plans**
- I create plans such as "Quiz, German, Mon/Wed/Fri 08:00, due words, 10 questions" or "Podcast,
  English, every day 19:30". A plan reviews flashcards, takes a quiz (which words, how many
  questions) or makes a podcast (level, length, style). Plans live under Practice; I can turn one
  off without losing it, and plans in a language I removed pause until I add it back.
- Each device schedules its own local notifications from the synced plans. The app asks for
  permission when I save my first plan, and tells me if notifications are off.
- Tapping a notification opens the activity, preconfigured: a review plan opens that language's
  flashcards when anything is due, a quiz plan starts the quiz, and a podcast plan writes a new
  episode with suggested words and opens it. `vocabularyos://plan/<id>` links do the same.
- iOS allows at most 64 pending notifications, so the app enforces that limit: a plan that would
  need more than 64 reminders a week, together with the others, can't be saved, and a device with
  more plans from other devices schedules the 64 that come soonest.
- *Accept when:* a plan for Mon/Wed/Fri at 08:00 produces three weekly repeating triggers (tests);
  the deep link opens the right screen.

**C11 — Sharing**
- Everything is private by default. Sharing happens only when I export.
- A list, or all words of a language, exports as a `.vocabularyos` file (versioned JSON) through the
  share sheet (AirDrop, Messages, Mail, Files). Opening the file imports it. Words with the same lemma
  and language are skipped.
- The file holds each word's explanation: the term, its dictionary form, the sentence, the
  translation, meaning, examples, other meanings and which AI explained it. Review history, photos
  and favorites stay on my devices.
- Before importing, I see how many words are new and how many I already have. Saved words stay as
  they are. A named list is created, or my list with that name is reused, and gets all the file's
  words. If the language isn't one I'm learning, it's added.
- Words can also export as CSV, for spreadsheets or Anki.
- *Accept when:* an export → import round trip is lossless; importing twice adds nothing; API keys
  and review history are never exported.

### Non-functional requirements
- **Privacy:**
  - No analytics, telemetry or tracking.
  - The only network calls go to the AI provider the user configured, and only when they use an AI
    feature.
  - User content is logged only with `privacy: .private`.
- **Offline:** the library, review, stored podcasts and on-device AI work without a network.
- **Accessibility:** Dynamic Type, VoiceOver labels on every control, sufficient contrast, and
  layouts that work on the smallest supported iPhone, in iPad split view and in a resizable Mac
  window.
- **Localization:** English and Turkish UI at launch, through String Catalogs. That includes the
  Share extension, error messages, reminders, the camera permission text, the word list file type and
  the Mac's Services menu item. Generated content stays in the languages the learner chose.
- **Performance:**
  - Library lists stay smooth with 10,000 words (paged fetches).
  - The capture sheet opens in under 300 ms.
- **Release:** an open-source repository with no secrets, Team IDs or personal data committed.

### Out of scope for v1
- Android, Windows, web, any server, user accounts beyond iCloud, payments.
- Real-time collaborative lists through CloudKit sharing (ADR-002 explains why files come first).
- Planned for v1.1, after the core:
  - Home Screen widget;
  - App Intents / Shortcuts;
  - live camera scanning (`DataScannerViewController`);
  - pronunciation practice (listen & say with the Speech framework).

## Tech Stack

| Area | Choice |
| --- | --- |
| Language | Swift 6.2, Swift 6 language mode with strict concurrency |
| Tooling | Xcode 26.2 or newer; XcodeGen 2.46 generates the Xcode project from `project.yml` |
| Platforms | iOS 26, iPadOS 26, macOS 26 (one multiplatform SwiftUI app target) |
| UI | SwiftUI with `@Observable` models |
| Storage and sync | SwiftData with CloudKit private database; iCloud key-value store for settings; Keychain (iCloud Keychain) for API keys |
| On-device AI | FoundationModels (`SystemLanguageModel`, `@Generable` guided generation) |
| Cloud AI | `URLSession` clients for OpenAI-compatible APIs and the Anthropic Messages API; no third-party SDKs |
| Vision | Vision `RecognizeDocumentsRequest` (page text with word boxes), `ClassifyImageRequest` (objects) |
| Language | NaturalLanguage (`NLLanguageRecognizer`, `NLTagger` lemma/lexical class, `NLTokenizer`) |
| Speech | AVFoundation `AVSpeechSynthesizer` |
| Scheduling | UserNotifications (`UNCalendarNotificationTrigger`) |
| Tests | Swift Testing for packages; XCTest UI tests for the core flow |
| Dependencies | None at runtime beyond Apple frameworks (ADR-006) |

## Commands

```bash
brew install xcodegen                                    # one-time
xcodegen generate                                        # writes VocabularyOS.xcodeproj from project.yml
swift test --package-path Packages/VocabularyKit         # all package tests on the Mac host
xcodebuild -project VocabularyOS.xcodeproj -scheme VocabularyOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project VocabularyOS.xcodeproj -scheme VocabularyOS \
  -destination 'platform=macOS' build
scripts/verify.sh                                        # generate + package tests + both app builds
swift run --package-path Packages/VocabularyKit vos-eval insight   # live on-device prompt evaluation (manual)
```

## Project Structure

```text
Vocabulary-OS/
├── project.yml                   XcodeGen spec; the .xcodeproj is generated and not committed
├── Config/                       xcconfigs, entitlements, Info.plist values
│   └── Signing.local.xcconfig    developer's Team ID and bundle prefix (gitignored)
├── App/                          multiplatform SwiftUI app: entry point, feature screens, resources
├── Extensions/ShareExtension/    share extension for iOS/iPadOS and macOS
├── Packages/VocabularyKit/       local Swift package with all logic and shared UI
│   ├── Sources/VocabularyCore      languages, SM-2, text selection, sentence context, validation (Foundation + NaturalLanguage only)
│   ├── Sources/VocabularyAI        provider catalog, clients, prompts, @Generable outputs, Keychain store
│   ├── Sources/VocabularyData      SwiftData models, repositories, settings store, extension inbox, import/export
│   ├── Sources/VocabularyCapture   page text recognition, object classification, thumbnails
│   ├── Sources/VocabularySpeech    text-to-speech playback
│   ├── Sources/VocabularyUI        SwiftUI views shared by the app and the share extension
│   ├── Sources/vos-eval            command-line prompt evaluation against the on-device model
│   └── Tests/<Module>Tests         one Swift Testing target per module
├── docs/                         ADR-NNN-title.md decision records
├── tasks/                        plan.md and todo.md (implementation plan)
├── scripts/verify.sh
├── SPEC.md · CLAUDE.md · README.md
```

Dependency direction:
- `VocabularyCore` ← `VocabularyAI`, `VocabularyData`, `VocabularyCapture`, `VocabularySpeech`
  ← `VocabularyUI` ← App and Share extension.
- `VocabularyCore` imports only Foundation and NaturalLanguage.
- No package module imports SwiftUI except `VocabularyUI`.

## Code Style

```swift
import Foundation

/// One SM-2 review step. Pure value logic: the same input always gives the same output.
public struct ReviewScheduler: Sendable {
    public var minimumEase = 1.3

    public init() {}

    public func schedule(_ card: CardState, rating: ReviewRating, now: Date, calendar: Calendar) -> CardState {
        var next = card
        if rating == .again {
            next.repetitions = 0
            next.lapses += 1
            next.intervalDays = 1
        } else {
            next.repetitions += 1
            next.intervalDays = switch next.repetitions {
            case 1: 1
            case 2: 6
            default: Int((Double(card.intervalDays) * card.ease).rounded())
            }
        }
        next.ease = max(minimumEase, card.ease + rating.easeDelta)
        let today = calendar.startOfDay(for: now)
        next.dueAt = calendar.date(byAdding: .day, value: next.intervalDays, to: today) ?? today
        return next
    }
}
```

Conventions:
- **Concurrency:** Swift 6 language mode. The app target uses default `MainActor` isolation; package
  types are `Sendable` values or actors. Use `async`/`await` and never Dispatch.
- **State:** `@Observable` for UI state; no `ObservableObject`. Dependencies are injected through
  initializers or protocols, with no singletons beyond what Apple frameworks require.
- **Errors:** typed enums conforming to `LocalizedError` with user-facing messages. No force unwraps
  or `try!` outside tests.
- **Logging:** `Logger(subsystem: "app.vocabularyos", category: …)`. User text uses
  `privacy: .private`. API keys are never logged in any form.
- **Comments:** explain *why*, not *what*. Public API gets a one-line doc comment.
- **Naming:** Swift API Design Guidelines; files named after their main type.

## Testing Strategy

- **Unit tests (most tests):** Swift Testing in each package module, run on the Mac host with
  `swift test`.
  - Core: scheduler, selection, sentence context, language routing, plan triggers, validators.
  - AI: request bodies for every provider family, response decoding (including malformed JSON), HTTP
    error mapping, the on-device two-step orchestration with a fake client.
  - Data: in-memory SwiftData CRUD, relationships, export/import, extension inbox.
  - Capture: Vision on generated page images, running on the host.
- **Integration:** `scripts/verify.sh` builds the app for the iOS Simulator and for macOS on every
  task. Each vertical slice is also checked in the simulator with screenshots. XCUITests cover
  capture → save → library, and sharing text from Reminders through the Share extension into the
  library (the Simulator has no Notes app). On macOS, `scripts/mac-smoke.sh --services` sends text
  through the Services menu and expects the capture window. Sharing on the Mac needs a signed build
  with the App Group, so the maintainer checks it at the checkpoint.
- **AI quality:** `vos-eval insight` runs fixed sentences against the on-device model and reports the
  right-sense rate and language adherence; `vos-eval quiz` checks that on-device quiz questions are
  valid and how fast the first one is ready; `vos-eval podcast` checks that on-device scripts use
  every chosen word. It runs before and after any prompt change, and results
  are recorded under `docs/eval/`. Cloud providers are checked manually with the maintainer's key and
  never in automated tests.
- **The iOS Simulator has no on-device model assets.** The framework reports the model as available,
  but generation then fails. Vision's image classifier doesn't run there either. So:
  - UI tests use canned AI answers (`-vos-ai-stub YES`);
  - the real on-device model is exercised on macOS by `vos-eval` and `scripts/mac-smoke.sh --self-test`,
    which captures a word inside the running app: from a sentence, from a generated book page, or
    by classifying and naming a photographed cup.
- **No network in tests:** HTTP is stubbed with a `URLProtocol` subclass.
- **Bugs:** a failing reproduction test comes before the fix (prove-it pattern).
- **Coverage goal:** about 90% of lines in VocabularyCore; at least 70% in AI and Data.

## Boundaries

- **Always:**
  - Run `scripts/verify.sh` before each commit.
  - One task per commit, with a Conventional Commit message in English that includes a scope, e.g.
    `feat(core): add SM-2 review scheduler`.
  - Keep the SwiftData schema CloudKit-compatible.
  - Check Apple APIs against the SDK interfaces or official documentation before using them, and
    cite them in ADRs.
  - Update this spec and the ADRs before changing course.
- **Ask first:**
  - Adding any third-party dependency.
  - Changing the SwiftData schema after the first public release (needs a migration plan).
  - Adding an AI provider, or sending a new kind of user data (for example photos) to a provider.
  - Raising the minimum OS.
  - Anything involving signing, entitlements, bundle IDs or the CloudKit container.
  - Rewriting published git history.
- **Never:**
  - Add a server, analytics or tracking.
  - Store API keys outside the Keychain, or log them.
  - Send user data to a provider the user did not select.
  - Commit secrets, Team IDs or personal data.
  - Skip or delete failing tests to get a green build.

## Success Criteria

v1 is done when all of these hold:
1. On an iPhone simulator and on a Mac, a new user finishes onboarding (native Turkish; learning
   English and German) in under a minute.
2. With no API key, "cookies" captured from "This website uses cookies for tracking." (in the app and
   from the share sheet) is saved as an English word with a Turkish translation and meaning.
3. A word from a German sentence lands in German automatically; an ambiguous single word can be
   corrected with one tap.
4. Tapping a word on a photographed page uses its full sentence as context, across line breaks.
5. An object photo becomes a saved word in the chosen learning language.
6. Review scheduling matches ADR-007 in unit tests; due counts are correct around midnight.
7. A 10-question quiz is generated and validated on device; its answers update review state.
8. A podcast script contains every chosen word and plays with on-device voices on iOS and macOS.
9. Plans schedule notifications, and the notification opens the planned activity.
10. Export → import round trips without loss or duplicates.
11. Words saved on one device appear on another device signed in to the same iCloud account
    (manual test with a signed build).
12. Network traffic goes only to the selected provider, and keys exist only in the Keychain
    (tests plus review).
13. `scripts/verify.sh` passes with no warnings from project code.

## Open Questions

1. **Signing identity:** Real iCloud sync, the App Group and a signed Mac build need an Apple
   Developer Team ID and a bundle ID prefix (for example `com.<you>.vocabularyos`). Until they are
   provided, the app runs locally without sync. That covers the simulator and an ad-hoc signed Mac
   build.
2. **License:** MIT or Apache-2.0 for the open-source release?
3. **Photos and cloud models:** for object capture, may the photo be sent to a vision-capable cloud
   model (opt-in), or should photos never leave the device (labels only)?
4. **Provider list:** is the list in C2 right?
5. **v1.1 items:** are the four items deferred to v1.1 acceptable?
