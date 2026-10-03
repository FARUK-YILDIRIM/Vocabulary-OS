# ADR-004: Multi-Language Architecture

**Status:** Accepted

**Date:** 2026-10-03

## Context

Users can simultaneously learn multiple languages. A single user might be Turkish, learning English and German at the same time. The system must organize words, detect language, and route learning content correctly.

## Decision

**Language-aware, multi-collection architecture:**

- **Auto-detection:** AI detects the source language of captured text
- **Automatic routing:** Words are stored in the appropriate language collection (e.g., "Englisch words", "German words")
- **Manual override:** User can correct detected language if needed
- **Shared learning pool:** All words feed into one unified spaced-repetition schedule (SM-2 algorithm)
- **Language tags:** Each word record includes detected language, source language, and user's native language
- **Content generation:** When generating podcast/quiz, AI respects the word's language context

### Example

User captures: "The book is on the table" (English) and "Das Buch ist auf dem Tisch" (German)
- "book" → English collection, TTS in English, quiz in English context
- "Buch" → German collection, TTS in German, quiz in German context
- Both appear in the same review schedule if user schedules both today

## Consequences

- **Positive:**
  - Users learn multiple languages simultaneously without switching apps
  - Language detection avoids user manual categorization (low friction)
  - Shared repetition schedule treats all words equally
  - Extensible: add more languages later without architectural change

- **Negative:**
  - AI must reliably detect language (edge case: code, names, mixed-language sentences)
  - Requires language-aware TTS (iOS Speech API supports 50+ languages natively)
  - Quiz generation must be language-aware (don't mix English/German distractors)

## Implementation Notes

- Use NaturalLanguage framework for language identification (fallback to AI if uncertain)
- iOS Speech API supports language tags; use them for TTS
- Quiz generation: "For a German word, use German distractors"
- Store language metadata on every word: `sourceLanguage`, `detectedLanguage`, `userNativeLanguage`

## Future Enhancements

- Language statistics dashboard (words per language, retention by language)
- Language-specific learning paths
- Dialect detection (e.g., British English vs. American English)
