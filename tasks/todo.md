# Vocabulary-OS v1 — Task Progress

Details and acceptance criteria are in [plan.md](plan.md). Tick a task only when its Definition of
Done holds and its commit exists.

## Phase 0: Define
- [x] D1 `docs(spec)`: rewrite SPEC.md around a capability map
- [x] D2 `docs(agents)`: rewrite CLAUDE.md as the rules file
- [x] D3 `docs(adr)`: correct ADR-001–005, add ADR-006–008
- [x] D4 `docs(plan)`: implementation plan and task list

## Phase 1: Foundation
- [x] T01 `chore(project)`: scaffold Xcode project, VocabularyKit package, verify script
- [ ] T02 `feat(core)`: language catalog and learner profile
- [ ] T03 `feat(data)`: synced settings store
- [ ] T04 `feat(app)`: onboarding and language settings
- [ ] Checkpoint 1: Foundation

## Phase 2: Meaning in context
- [ ] T05 `feat(core)`: term selection and sentence context
- [ ] T06 `feat(core)`: language routing
- [ ] T07 `feat(ai)`: generation client contract and Apple on-device client
- [ ] T08 `feat(ai)`: word insight service with validation
- [ ] T09 `feat(ai)`: vos-eval prompt evaluation
- [ ] T10 `feat(data)`: SwiftData schema v1 and word repository
- [ ] T11 `feat(capture)`: in-app text capture
- [ ] T12 `feat(library)`: library and word detail
- [ ] Checkpoint 2: Core slice

## Phase 3: Bring-your-own-key providers
- [ ] T13 `feat(ai)`: provider catalog and Keychain secret store
- [ ] T14 `feat(ai)`: OpenAI-compatible client
- [ ] T15 `feat(ai)`: Anthropic Messages client
- [ ] T16 `feat(settings)`: AI provider settings and cloud insight path
- [ ] Checkpoint 3: Providers

## Phase 4: Capture everywhere
- [ ] T17 `feat(share)`: share extension inbox (iOS)
- [ ] T18 `feat(share)`: macOS share extension and Services menu
- [ ] T19 `feat(capture)`: page text recognition
- [ ] T20 `feat(capture)`: page capture screen
- [ ] T21 `feat(capture)`: object capture
- [ ] Checkpoint 4: Capture

## Phase 5: Practice
- [ ] T22 `feat(core)`: SM-2 scheduler and daily queue
- [ ] T23 `feat(review)`: flashcard review and Today screen
- [ ] T24 `feat(ai)`: quiz generation and validation
- [ ] T25 `feat(quiz)`: quiz session and grading
- [ ] T26 `feat(speech)`: speech engine
- [ ] T27 `feat(podcast)`: podcast script generation
- [ ] T28 `feat(podcast)`: podcast setup and player
- [ ] Checkpoint 5: Practice

## Phase 6: Plans, sharing, polish
- [ ] T29 `feat(plans)`: study plans and notifications
- [ ] T30 `feat(sharing)`: export and import
- [ ] T31 `feat(i18n)`: Turkish localization
- [ ] T32 `feat(ui)`: accessibility and polish
- [ ] T33 `docs(release)`: open-source release readiness
- [ ] Checkpoint 6: Ship
