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
- [x] T28 `feat(podcast)`: podcast setup and player — on-device writing and playback with system voices checked by the macOS self-test
- [ ] Checkpoint 5: Practice — automated checks passed 2026-10-04: flashcard review, quizzes and
  podcasts run in the UI tests on iPhone and iPad with canned answers, and an episode plays to its
  end in the Simulator; on the Mac, the on-device model writes quiz questions (4/4 valid) and podcast
  episodes (7–13 s each) in the self-tests, and Samantha and Daniel speak them. Owner checks: podcast
  audio on a device, with the screen locked and with music playing; whether the voices and the
  shorter-than-asked episodes are good enough (T32). Awaiting owner review.

## Phase 6: Plans, sharing, polish
- [x] T29 `feat(plans)`: study plans and notifications — the reminder scheduler lives in VocabularyData so the package tests cover it
- [x] T30 `feat(sharing)`: export and import — with the list management deferred from T12
- [x] T31 `feat(i18n)`: Turkish localization — verify.sh now keeps the catalogs in step and requires Turkish
- [x] T32 `feat(ui)`: accessibility and polish — the main screens pass the system audit at the default and the largest text size; the items noticed in T20, T27 and T28 are done

## Phase 7: The owner's answers and the ship review
- [ ] T33 `feat(capture)`: object photos for cloud models, opt-in (owner's answer 3)
- [ ] T34 `feat(ai)`: more providers and learner-added providers (owner's answer 4)
- [ ] T35 `fix`: ship review findings (code, security and test reviews)
- [ ] T36 `docs(release)`: open-source release readiness
  - Noticed while building T29:
    - Info.plist lacks the `remote-notification` background mode that ADR-002 lists for CloudKit
      sync, so changes from other devices arrive only while the app is open;
    - `scripts/mac-smoke.sh` counts only windows on the current Space, so it reports no window while
      another app is full screen.
  - Noticed while building T30: the macOS build warns that `NSCameraUsageDescription` is empty (it is
    set for iOS only in project.yml), and `scripts/verify.sh` only catches warnings in source files.
- [ ] Checkpoint 6: Ship
