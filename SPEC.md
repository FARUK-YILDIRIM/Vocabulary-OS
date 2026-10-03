# Vocabulary-OS Specification

## Overview

**Vocabulary-OS** is a privacy-first, multi-language learning app for Apple platforms. Users capture words from text, books, and objects in context, then reinforce learning through AI-generated podcasts, quizzes, and spaced repetition.

See [`docs/`](docs) for architectural decisions (ADRs).

## Core Features

### 1. Word Capture

**Sources:**
- **Manual input:** Type or paste text (phrase or single word)
- **Text selection:** Highlight text in any source, trigger capture
- **Document scanning:** Photograph a book page, extract text, select words
- **Object capture:** Photograph an object, get description/translation

**Capture metadata:**
- Selected word
- Full sentence context
- Source language (auto-detected)
- Image (optional: page photo or object photo)
- Timestamp
- Collection (user can organize)

### 2. Word Collections

Users organize words into collections:
- Language-based (auto-generated: "English words", "German words", etc.)
- Custom user collections ("Travel German", "Business English", etc.)
- Shared collections (optional, user controls sharing)

**Constraints:**
- Words in a collection are language-consistent (one collection = one language)
- A word can appear in multiple collections
- Collections sync across all devices

### 3. Learning & Reinforcement

**Spaced Repetition (SM-2):**
- Schedule words for review based on difficulty and retention
- Daily review limit (configurable, default 10 words/day)
- Review history logged (helps algorithm adjust intervals)

**Quiz Generation (AI):**
- Multiple choice (user selects meaning)
- Fill-the-gap (user completes sentence)
- Translate (user provides translation in native language)
- Variety: 3-4 words per quiz session, randomized

**Podcast Generation (AI):**
- Creates a short 5-10 minute podcast episode
- Narrates stories/examples using the captured words
- Uses word context (from the original sentence)
- TTS in target language

**Scheduling:**
- User can schedule learning sessions (e.g., "review at 9am daily")
- Notifications remind user (local notifications, no server)
- User can defer or reschedule

### 4. Multi-Language Support

- User specifies native language (L1) and target languages (L2, L3, etc.)
- Words are auto-detected by language
- Learning content (quiz, podcast) respects language context
- User can learn English and German simultaneously
- AI auto-detects source language of captured text

### 5. AI Provider Integration

**Defaults:**
- Foundation Models (on-device, free, iOS 18.2+)
- Falls back to Foundation Models if no token provided

**Supported Providers:**
- OpenAI
- DeepSeek
- OpenRouter
- Any OpenAI-compatible API

**User Flow:**
1. Settings → AI Provider
2. Choose provider (or "Use on-device model")
3. If chosen, paste API token
4. App tests token, stores in Keychain
5. Every request uses user's account/quota

## Screens & Flows

### 1. Onboarding

- Welcome screen
- Language selection (native + target languages)
- AI provider setup (offer on-device default)
- iCloud sync explanation (optional)

### 2. Home Tab

- "Today's review" widget (words due for review today)
- "Recent words" list (last 10 captured)
- "Start review session" button
- "Capture word" floating button (always accessible)

### 3. Capture Flows

**Flow A: Manual Text**
1. Tap "Capture word"
2. Choose source: "Type text" / "Photograph page" / "Photograph object"
3. (If type): Enter/paste text
4. (If photograph): Camera → select word from recognized text
5. Review: show context sentence
6. Select collection
7. Save

**Flow B: Document Scanning**
1. Camera live feeds text recognition
2. User taps words to select
3. Dialog shows: word + context sentence
4. Confirm and save

**Flow C: Object**
1. Camera → photograph object
2. App shows: "What is this?" (optional AI description)
3. User can accept or edit description
4. Saves as word entry with photo

### 4. Collections Tab

- List all collections (language auto-generated + user custom)
- For each: word count, last studied, next review
- Tap collection → see words, review options
- Share button (generates shareable link)

### 5. Learning Tabs

- **Today's Review:** words due today, quiz/podcast buttons
- **History:** past review sessions, retention graph
- **Settings:** language preferences, AI provider, notification schedule

### 6. Settings

- Native language
- Target languages (add/remove)
- AI provider (choose, test, switch)
- Notifications (enable, time, frequency)
- iCloud sync (show status, manual refresh)
- About (version, credits, privacy policy)

## Data Model

### Word

```
id: UUID
collectionId: UUID
sourceLanguage: String (e.g., "en", "de")
word: String
context: String (full sentence)
image: Data? (page photo or object photo, stored as thumbnail)
aiGeneratedContent: {
  description: String? (AI-generated explanation)
  examples: [String]
}
createdAt: Date
lastReviewedAt: Date?
nextReviewAt: Date?
retentionScore: Double (0-1, SM-2)
reviewCount: Int
difficultyRating: Int (1-5, user's assessment)
```

### Collection

```
id: UUID
name: String (e.g., "English words" or "Travel German")
language: String (detected from words)
isShared: Bool
shareToken: String? (if shared)
wordIds: [UUID]
createdAt: Date
updatedAt: Date
```

### LearningSession

```
id: UUID
collectionId: UUID
startedAt: Date
finishedAt: Date?
wordIds: [UUID] (words reviewed in this session)
results: [
  {
    wordId: UUID
    questionType: String ("multiple-choice" | "fill-gap" | "translate")
    correct: Bool
    userResponse: String?
    elapsedSeconds: Int
  }
]
```

## Acceptance Criteria

### Phase 1: Core (M1-M4)

- [ ] SwiftUI app runs on iOS 18.2 simulator
- [ ] SwiftData models persist locally
- [ ] CloudKit sync works with test iCloud account
- [ ] Manual text capture stores word + context
- [ ] SM-2 algorithm schedules reviews correctly
- [ ] Foundation Models AI provider generates quiz/podcast
- [ ] Multi-language detection works (English, German, Turkish at minimum)
- [ ] All tests pass (`swift test`)
- [ ] No crashes in simulator

### Phase 2: Vision & macOS (M5-M6)

- [ ] Document camera scanning extracts text
- [ ] Object photography works
- [ ] macOS UI matches iOS (SwiftUI shared code)
- [ ] Global shortcut works (macOS Services menu)
- [ ] Cross-device sync tested (iPhone + Mac)

### Phase 3: Polish (M7+)

- [ ] User notifications work
- [ ] Sharing UX tested
- [ ] OpenAI provider integration tested
- [ ] Onboarding flow complete
- [ ] App Store submission ready (icons, screenshots, privacy policy)

## Non-Functional Requirements

- **Performance:** Word capture response < 1s, quiz generation < 5s
- **Privacy:** No data leaves device except CloudKit sync; user tokens in Keychain only
- **Reliability:** Offline-first (local data always available); sync when online
- **Accessibility:** VoiceOver support, high contrast option
- **Testing:** Unit tests for SM-2, AI provider abstraction, data model; UI tests for capture flows

## Out of Scope

- Backend server
- Billing or In-App Purchases
- Analytics or telemetry
- Cross-device notifications (local only)
- Social features (sharing is manual link-based)
- Browser extension
- Web app
