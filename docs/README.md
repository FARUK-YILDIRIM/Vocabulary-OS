# Vocabulary-OS Architecture Decision Records

This directory contains the architectural decisions for Vocabulary-OS, documented using the ADR (Architecture Decision Record) format.

## ADRs

| # | Title | Status | Date |
|---|-------|--------|------|
| [001](ADR-001-apple-only-platform.md) | Apple-Only Platform | Accepted | 2026-10-03 |
| [002](ADR-002-cloudkit-private-data-architecture.md) | CloudKit Private Data Architecture | Accepted | 2026-10-03 |
| [003](ADR-003-byok-ai-provider-model.md) | BYOK (Bring Your Own Key) AI Provider Model | Accepted | 2026-10-03 |
| [004](ADR-004-multilingual-architecture.md) | Multi-Language Architecture | Accepted | 2026-10-03 |
| [005](ADR-005-vision-and-object-capture.md) | Vision and Object Capture | Accepted | 2026-10-03 |

## Reading Guide

Start with ADR-001 to understand the platform choice. Each ADR builds on the previous decisions:

- **ADR-001** → Platform scope (Apple-only)
- **ADR-002** → Data storage (CloudKit private)
- **ADR-003** → AI integration (BYOK model)
- **ADR-004** → Multi-language support
- **ADR-005** → Capture mechanisms (text, objects)

## Adding New ADRs

When a significant architectural decision arises, create a new ADR:

1. Copy the template format
2. Use the next available number
3. Update this README
4. Link related ADRs

Format: `ADR-NNN-kebab-case-title.md`
