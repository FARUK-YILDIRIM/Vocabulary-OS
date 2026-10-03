# ADR-002: CloudKit Private Data Architecture

**Status:** Accepted

**Date:** 2026-10-03

## Context

Vocabulary-OS stores all user data: captured words, collections, learning schedules, AI provider tokens, and generated content. The system must keep data private by default, allow optional sharing, and sync across devices with zero backend infrastructure.

## Decision

Use **CloudKit private database** as the primary data store:

- **Private database:** User data lives in their iCloud account, encrypted by default
- **SwiftData + CloudKit:** SwiftData models automatically sync via CloudKit when configured with `.cloudKitContainer(identifier:)`
- **Sharing:** Users can explicitly share collections or word lists via CloudKit sharing (generates a link/record share)
- **No server:** No backend service, no third-party database

### Data Model Layers

1. **Local-first:** SwiftData models on-device, synced automatically
2. **Encrypted transit:** CloudKit handles encryption to/from iCloud
3. **User isolation:** Each user's container is separate; no cross-user visibility
4. **Optional sharing:** User opts into sharing specific collections; revocable anytime

## Consequences

- **Positive:**
  - Zero backend ops, zero server costs
  - User data never touches our servers
  - iCloud sync is automatic and free
  - Sharing is opt-in and granular
  - Complies with "data minimization" privacy principle

- **Negative:**
  - Requires iOS 17+ (SwiftData) and iOS 16.1+ (CloudKit sync)
  - Users must have iCloud account (Apple ID)
  - Sharing flow adds UI complexity
  - No server-side analytics or moderation (good for privacy, harder for metrics)

## Notes

- Research Apple's CloudKit documentation on `CKModifyRecordsOperation` and sharing semantics
- Test with multiple iCloud accounts to validate sync behavior
- Implement conflict resolution strategy (last-write-wins vs. user choice)
