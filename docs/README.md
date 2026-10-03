# Architecture Decision Records

Each ADR records one decision that would be expensive to reverse: its context, the alternatives and
the consequences. ADRs are never deleted. When a decision changes, a new ADR supersedes the old one,
and the old one's status says so.

| ADR | Title | Status |
| --- | --- | --- |
| [001](ADR-001-apple-only-platform.md) | Apple-only platform, iOS/iPadOS/macOS 26 minimum | Accepted (revised) |
| [002](ADR-002-cloudkit-private-data-architecture.md) | Private iCloud data, extension hand-off, and file-based sharing | Accepted (revised) |
| [003](ADR-003-byok-ai-provider-model.md) | On-device AI by default, bring-your-own-key cloud providers | Accepted (revised) |
| [004](ADR-004-multilingual-architecture.md) | Multiple learning languages with automatic routing | Accepted (revised) |
| [005](ADR-005-vision-and-object-capture.md) | Capture from text, book pages and objects | Accepted (revised) |
| [006](ADR-006-project-structure-and-tooling.md) | Project structure, tooling and build configurations | Proposed |
| [007](ADR-007-spaced-repetition-sm2.md) | Spaced repetition with SM-2 and four ratings | Proposed |
| [008](ADR-008-podcast-audio-on-device-tts.md) | Podcasts as AI scripts spoken with on-device voices | Proposed |

ADR-001 to 005 record decisions the owner made on 2026-10-03. On 2026-10-04 they were revised
after checking the facts against the iOS/macOS 26.2 SDK and Apple's documentation. The first drafts
named APIs and OS versions that do not exist. ADR-006 to 008 are implementation decisions awaiting
the owner's review.

## Template

```markdown
# ADR-NNN: <decision as a short phrase>

## Status
Proposed | Accepted | Superseded by ADR-XXX | Deprecated

## Date
YYYY-MM-DD

## Context
## Decision
## Alternatives Considered
## Consequences
## Sources
```
