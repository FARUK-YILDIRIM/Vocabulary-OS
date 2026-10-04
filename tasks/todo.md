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
- [x] T02 `feat(core)`: language catalog and learner profile
- [x] T03 `feat(data)`: synced settings store
- [x] T04 `feat(app)`: onboarding and language settings
- [ ] Checkpoint 1: Foundation — automated checks passed 2026-10-04 (verify, UI test on iPhone and iPad, macOS smoke); awaiting owner review

## Phase 2: Meaning in context
- [x] T05 `feat(core)`: term selection and sentence context
- [x] T06 `feat(core)`: language routing
- [x] T07 `feat(ai)`: generation client contract and Apple on-device client
- [x] T08 `feat(ai)`: word insight service with validation
- [x] T09 `feat(ai)`: vos-eval prompt evaluation
- [x] T10 `feat(data)`: SwiftData schema v1 and word repository
- [x] T11 `feat(capture)`: in-app text capture
- [x] T12 `feat(library)`: library and word detail
- [ ] Checkpoint 2: Core slice — automated checks passed 2026-10-04 (UI tests with canned AI on iPhone and iPad, real on-device capture in the macOS app, vos-eval 10/10 senses); awaiting owner review

## Phase 3: Bring-your-own-key providers
- [x] T13 `feat(ai)`: provider catalog and Keychain secret store
- [x] T14 `feat(ai)`: OpenAI-compatible client
- [x] T15 `feat(ai)`: Anthropic Messages client
- [x] T16 `feat(settings)`: AI provider settings and cloud insight path
- [ ] Checkpoint 3: Providers — automated checks passed 2026-10-04 (stubbed HTTP tests for every provider family, AI settings UI test, on-device self-test on macOS); a live cloud test needs the owner's API key

## Phase 4: Capture everywhere
- [x] T17 `feat(share)`: share extension inbox (iOS)
- [x] T18 `feat(share)`: macOS share extension and Services menu — sharing from Safari needs a signed build (owner)
- [x] T19 `feat(capture)`: page text recognition
- [x] T20 `feat(capture)`: page capture screen
- [x] T21 `feat(capture)`: object capture — on-device naming checked by the macOS self-test (the Simulator has neither the model nor the classifier)
- [ ] Checkpoint 4: Capture — automated checks passed 2026-10-04: text, share sheet (from Reminders),
  page and object capture save words in the UI tests on iPhone and iPad; the Services menu opens the
  capture window on the Mac; page and object capture work with the real on-device model in the macOS
  self-tests. Owner checks: sharing on the Mac in a signed build, the Mac file picker, the camera on a
  device. Awaiting owner review.

## Phase 5: Practice
- [x] T22 `feat(core)`: SM-2 scheduler and daily queue
- [x] T23 `feat(review)`: flashcard review and Today screen
- [x] T24 `feat(ai)`: quiz generation and validation
- [x] T25 `feat(quiz)`: quiz session and grading — listening questions come with the speech engine (T26)
- [x] T26 `feat(speech)`: speech engine — also enables listening quiz questions
- [x] T27 `feat(podcast)`: podcast script generation
- [ ] T28 `feat(podcast)`: podcast setup and player
- [ ] Checkpoint 5: Practice

## Phase 6: Plans, sharing, polish
- [ ] T29 `feat(plans)`: study plans and notifications
- [ ] T30 `feat(sharing)`: export and import
- [ ] T31 `feat(i18n)`: Turkish localization
- [ ] T32 `feat(ui)`: accessibility and polish
  - Noticed while building T20:
    - drag-and-drop photos onto page capture (ADR-005);
    - in the selectable text, punctuation can wrap to the next line away from its word;
    - under a capture, "Explained by" names the selected provider instead of the insight's source,
      which only differs with canned test answers.
- [ ] T33 `docs(release)`: open-source release readiness
- [ ] Checkpoint 6: Ship
