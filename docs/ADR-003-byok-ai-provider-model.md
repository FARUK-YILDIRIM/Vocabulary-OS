# ADR-003: BYOK (Bring Your Own Key) AI Provider Model

**Status:** Accepted

**Date:** 2026-10-03

## Context

Vocabulary-OS generates podcasts and quizzes using AI. The team must decide: host a backend that calls AI APIs on behalf of users (SaaS model), or let users provide their own credentials (BYOK)?

## Decision

**Bring Your Own Key (BYOK) model:** User provides their API token; the app calls the AI provider directly from the device.

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

## Consequences

- **Positive:**
  - Zero AI hosting costs for us
  - No backend needed to call AI APIs
  - Users pay only for what they use (or use free on-device model)
  - No rate limiting on our side
  - Users control which provider/model

- **Negative:**
  - UX burden: users must create accounts and manage tokens
  - Users pay for API calls directly
  - Support complexity: debugging user's provider issues
  - Quality varies by provider choice

## Alternative Considered

- **SaaS model:** We host the API calls, charge users. **Rejected** because it requires a backend, adds operational cost, and violates the "user owns data" principle (we'd see all requests).

## Notes

- Foundation Models: research Apple's MLX inference, quantized model sizes, supported architectures
- OpenAI-compatible: standardize on the Chat Completions API format
- Keychain storage: use `SecureEnclave` if available for token encryption
- Test with multiple providers to validate compatibility layer
