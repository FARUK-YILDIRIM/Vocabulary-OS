# ADR-003: BYOK (Bring Your Own Key) AI Provider Model

**Status:** Accepted

**Date:** 2026-10-03

## Context

Vocabulary-OS uses AI in three critical ways:

1. **Word context understanding:** When user captures a single word or phrase, AI analyzes the full sentence context to understand which meaning/translation is relevant
2. **Content generation:** AI generates quizzes (multiple choice, fill-gap, translate) and podcast episodes using captured words
3. **Language awareness:** AI detects source language and provides explanations/translations in user's native language

The team must decide: host a backend that calls AI APIs on behalf of users (SaaS model), or let users provide their own credentials (BYOK)?

## Decision

**Bring Your Own Key (BYOK) model:** User provides their API token; the app calls the AI provider directly from the device.

### AI Usage Flows

1. **Word capture with context:** User captures "cookie" from sentence "This website uses cookies for tracking"
   - App sends: full sentence + selected word + user's native language
   - AI responds: meaning in context, translation, brief explanation
   - Result stored with word (no repeated AI calls for same word)

2. **Quiz generation:** User starts review session
   - App sends: word, context, user's native language, quiz type
   - AI generates: multiple choice options, fill-gap sentences, translation challenges
   - Response cached for this session

3. **Podcast generation:** User requests learning podcast
   - App sends: 3-5 words, contexts, user's native language, target language
   - AI generates: short narrative (5-10 min) using these words naturally
   - Podcast narrated via iOS Speech API

### Providers Supported

- **Foundation Models (default):** iOS 18.2+ on-device inference, free, no token needed
- **OpenAI-compatible APIs:** OpenAI, DeepSeek, OpenRouter, Anthropic (when compatible), others
- **Provider selection UI:** Users pick their provider, paste their token, app remembers it (in Keychain)
- **Fallback:** If no token, use Foundation Models (capped quality, but always works)

### User Flow

1. First launch: app offers "Use on-device model (free, limited)" or "Connect your provider"
2. User chooses → enters token → app tests it
3. Token stored in Keychain (encrypted, never logged)
4. Each request uses their account, their quota
5. All AI requests include: full context (sentence/phrase), selected word, user's native language

### Request/Response Contract

**Word context request:**
```json
{
  "type": "word_context",
  "selectedWord": "cookie",
  "fullSentence": "This website uses cookies for tracking",
  "userNativeLanguage": "tr",
  "targetLanguage": "en"
}
```

**Response:**
```json
{
  "word": "cookie",
  "meaning": "A small file stored on your computer",
  "translation": "Çerez",
  "explanation": "In this context, it refers to tracking cookies used by websites",
  "examples": ["Privacy cookies track user behavior"]
}
```

## Consequences

- **Positive:**
  - Zero AI hosting costs for us
  - No backend needed to call AI APIs
  - Users pay only for what they use (or use free on-device model)
  - No rate limiting on our side
  - Users control which provider/model
  - Context-aware understanding happens on user's device (their sentence, their language)
  - All AI calls include full context (not just word); quality improves

- **Negative:**
  - UX burden: users must create accounts and manage tokens
  - Users pay for API calls directly
  - Support complexity: debugging user's provider issues
  - Quality varies by provider choice
  - Requires careful prompt design to get consistent context-aware responses
  - Word capture latency depends on AI provider response time (mitigated by caching)

## Alternative Considered

- **SaaS model:** We host the API calls, charge users. **Rejected** because it requires a backend, adds operational cost, and violates the "user owns data" principle (we'd see all requests).

## Implementation Notes

- **Prompt design:** Context-aware prompts for word understanding (send sentence, not just word)
- **Caching:** Cache word explanations to avoid repeated API calls
- **Error handling:** If AI request fails, show local fallback (word + sentence only, no AI explanation)
- **Foundation Models:** Research Apple's MLX inference, quantized model sizes, supported architectures
- **OpenAI-compatible:** Standardize on the Chat Completions API format
- **Keychain storage:** Use `SecureEnclave` if available for token encryption
- **Testing:** Test with multiple providers to validate compatibility; use real sentences as test data
- **Latency:** Measure word capture latency; add loading indicator if > 500ms
