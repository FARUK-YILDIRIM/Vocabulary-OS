# ADR-001: Apple-Only Platform

**Status:** Accepted

**Date:** 2026-10-03

## Context

Vocabulary-OS is a learning tool for capturing words from text, books, and objects, then reinforcing them through AI-generated podcasts, quizzes, and spaced repetition. The team must decide which platforms to support initially.

## Decision

Build exclusively for Apple platforms: **iOS, iPadOS, and macOS**.

This is a deliberate constraint, not a tradeoff to optimize. The decision leverages Apple's ecosystem strengths:

- **Native frameworks:** SwiftUI, SwiftData, CloudKit, Vision API, Speech API are production-ready and well-integrated
- **Continuity:** Users work seamlessly across iPhone → iPad → Mac with automatic sync
- **Privacy by design:** CloudKit private database keeps user data on-device and in iCloud, never on our servers
- **On-device AI:** Foundation Models framework (iOS 18.2+) runs AI inference without sending data to third parties
- **Share extensions:** iOS and macOS native integration (not web-based)
- **Keyboard and trackpad:** macOS gives power users a superior experience

## Consequences

- **Positive:**
  - Simpler codebase: single language (Swift), single paradigm (SwiftUI)
  - No backend to maintain
  - No multi-platform UI inconsistencies
  - Faster iteration with AI agents (consistent tooling)
  - Users own their data completely

- **Constraints:**
  - Only reaches users in Apple ecosystem (estimated ~27% of global smartphone users; higher in developed markets)
  - Requires Apple Developer account ($99/year)
  - Must follow App Store guidelines and review process
  - Device minimum: iOS 18.2+ (for Foundation Models); iOS 16+ for base features

## Notes

- Android, Web, and Windows are explicitly out of scope
- This is a strength (focus) not a weakness (limitation)
