# Vocabulary-OS Milestones

Development is organized into 7 milestones. Each milestone has clear inputs, outputs, and acceptance criteria.

## Milestone 1: Data Models & SwiftData (M1)

**Goal:** Establish the local data layer that everything else builds on.

**Deliverables:**
- SwiftData `@Model` classes: `Word`, `Collection`, `LearningSession`
- CloudKit metadata (ready for M2)
- Unit tests for all models (CRUD, relationships)
- Sample seed data for testing

**Done When:**
- [ ] All models compile without warnings
- [ ] CRUD operations work: create word, add to collection, query by language
- [ ] Relationships are correct: collection → words (1:many), session → words
- [ ] 15+ unit tests pass
- [ ] Seed data loads in simulator

**Estimate:** 2 days

---

## Milestone 2: CloudKit Sync (M2)

**Goal:** Implement iCloud sync so data persists and syncs across devices.

**Deliverables:**
- SwiftData + CloudKit configuration
- Sync logic (on-device first, then CloudKit)
- Conflict resolution strategy
- Test with multiple iCloud accounts

**Done When:**
- [ ] Create word on iPhone simulator, sync to Mac simulator
- [ ] Modify word on Mac, iPhone reflects change
- [ ] Offline create, then sync when online
- [ ] CloudKit dashboard shows data in correct container
- [ ] 10+ sync integration tests pass

**Estimate:** 2 days

---

## Milestone 3: SM-2 Spaced Repetition Algorithm (M3)

**Goal:** Implement the review scheduling engine.

**Deliverables:**
- SM-2 algorithm (calculus from Supermemo)
- Review session generator (which words are due today?)
- Difficulty rating input (user marks "hard", "easy", etc.)
- Review history tracker

**Done When:**
- [ ] Algorithm correctly calculates next review date
- [ ] 20+ algorithm test cases pass
- [ ] Easy word: interval increases by ~2.6x
- [ ] Hard word: interval resets to 1 day
- [ ] Retention score is calculated
- [ ] Review sessions don't show words due tomorrow (or later)

**Estimate:** 1 day

---

## Milestone 4: Manual Text Capture & SwiftUI (M4)

**Goal:** First user-visible feature: capture a word by typing/pasting, save it, view it.

**Deliverables:**
- iOS SwiftUI screens: Home, CaptureSheet, CollectionDetail
- Manual text input (TextEditor for context, TextField for word)
- Collection selection/creation UI
- List of captured words
- Integration with M1 (SwiftData) and M3 (SM-2)

**Done When:**
- [ ] Tap floating button → capture sheet opens
- [ ] Enter word and context → saves to local database
- [ ] Word appears in collection list immediately
- [ ] Collection shows word count, last studied, next review
- [ ] Tap word → see full details + context + image placeholder
- [ ] Simulator shows data without crashes
- [ ] 10+ SwiftUI snapshot tests pass

**Estimate:** 2 days

---

## Milestone 5: Vision & Document Scanning (M5)

**Goal:** Capture words from book page photos using OCR.

**Deliverables:**
- Camera integration (VisionKit or Vision API)
- Real-time text recognition from live camera
- Word selection UI (user highlights text)
- Image compression and storage
- Integration with M4 capture flow

**Done When:**
- [ ] Camera permission flows work
- [ ] Live camera feed shows text recognition boxes
- [ ] User taps a word → shows context + save
- [ ] Page photo stored with word metadata
- [ ] OCR accuracy tested with real book photo (white paper, clear font)
- [ ] Thumbnail image stored (not full resolution)
- [ ] 5+ Camera integration tests pass

**Estimate:** 2 days

---

## Milestone 6: AI Providers & Quiz/Podcast Generation (M6)

**Goal:** Generate learning content (quiz and podcast) from captured words.

**Deliverables:**
- `LLMProvider` protocol (abstract AI interface)
- Foundation Models adapter (on-device)
- OpenAI-compatible adapter (for OpenAI, DeepSeek, OpenRouter)
- Quiz generator (multiple choice, fill-gap, translate)
- Podcast generator (short narration with TTS)
- Settings UI for provider selection/token input
- Keychain storage for tokens

**Done When:**
- [ ] Foundation Models generates quiz for a word (offline, instant)
- [ ] User can paste OpenAI token → test → app generates quiz via API
- [ ] Quiz has 3-4 answer options, correct answer works
- [ ] Podcast episode generates in < 5 seconds
- [ ] TTS works in multiple languages (English, German, Turkish)
- [ ] Token stored in Keychain (not logs or defaults)
- [ ] 10+ AI provider tests pass (mocked)

**Estimate:** 3 days

---

## Milestone 7: macOS, Global Shortcut & Polish (M7)

**Goal:** Extend to macOS, add global keyboard shortcut, complete UI.

**Deliverables:**
- macOS app (share code with iOS via SwiftUI)
- Global shortcut registration (Cmd+Shift+L to capture)
- macOS Services menu integration
- Dark mode support
- Accessibility (VoiceOver, text scaling)
- App icon, launch screen
- Onboarding flow (language selection, AI setup)
- Notification scheduling

**Done When:**
- [ ] macOS app launches, shows home screen
- [ ] Cmd+Shift+L triggers capture sheet from any app
- [ ] iPhone + Mac sync words in real-time
- [ ] Dark mode looks correct
- [ ] VoiceOver can navigate app
- [ ] Onboarding guides new user through setup
- [ ] Local notifications trigger at scheduled time
- [ ] 10+ macOS integration tests pass

**Estimate:** 3 days

---

## Summary

| Milestone | Phase | Days | Key Output |
|-----------|-------|------|-----------|
| M1 | Core | 2 | SwiftData models, tests |
| M2 | Core | 2 | CloudKit sync |
| M3 | Core | 1 | SM-2 algorithm |
| M4 | Core | 2 | Manual capture UI |
| M5 | Vision | 2 | Document scanning |
| M6 | AI | 3 | Quiz/podcast generation |
| M7 | Polish | 3 | macOS, global shortcut, onboarding |

**Total estimate:** ~15 days of AI agent work.

Each milestone is developed by AI agents, reviewed by the human, then committed. No milestone starts until the previous one is accepted.
