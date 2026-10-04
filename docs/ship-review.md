# Ship review: Vocabulary-OS 0.1

Date: 2026-10-04. The GO decision is the owner's; this document gives the recommendation and what
it rests on.

## Recommendation

- **GO for publishing the repository** under the MIT license. No Critical finding was found, and
  every High finding is fixed. The open findings are listed below with their reasons.
- **NO-GO for TestFlight or the App Store until the owner's checks pass.** iCloud sync, the Mac
  share sheet, the camera, background audio and every cloud provider have only been tested with
  stand-ins. The checks are in [Before a store release](#before-a-store-release).

## How the review was done

Three reviews ran independently on the tree after T32 (`92ae5a4`). Each reviewer read the code and
documentation without building it.

- **Code:** correctness, data loss, crashes, concurrency, sync and edge cases.
- **Security:** key handling, network, untrusted input, prompt injection, data at rest, entitlements
  and logging.
- **Tests:** coverage of the SPEC's acceptance and success criteria, tests that can't fail, flaky
  tests and test doubles.

T34 fixed two findings while adding providers, and T35 fixed the rest that are marked fixed below,
in commits `5c980b3` to `f864d63`. Each fix has a test unless the table says otherwise.

## Findings

Severity: Critical (data loss, a crash on a common path, a broken core feature), High, Medium,
Low, Info.

### Code review

| # | Severity | Finding | Outcome |
| --- | --- | --- | --- |
| 1 | High | A word store that can't be opened was silently replaced by an in-memory one, and the Share extension's inbox was imported into it and deleted | Fixed in `5c980b3`: the app shows only an error and leaves the inbox alone (UI test) |
| 2 | High | The versioned schema listed the live model classes, so the first model change would stop the store from opening | Fixed in `5c980b3`: no versioned schema until a change needs a migration stage; SwiftData migrates added properties itself (tests reopen a store on disk and add a property) |
| 3 | Medium | Synced settings or inbox drafts this version can't read were thrown away, sending the learner back to onboarding | Fixed in `4af8f41`: unknown learning languages are left out, unreadable changes keep the current setting, unreadable drafts are set aside |
| 4 | Medium | Changing the language chip while explaining saved the word in the old language | Fixed in `2ac2ed2` (test with a slow model) |
| 5 | Medium | Every cloud request timed out after 60 s, so long podcasts and quizzes failed with a misleading message | Fixed in `d6b6bf3`: long answers get 300 s and a "took too long" message; responses are still not streamed |
| 6 | Medium | A provider at `localhost` chosen on one device was used by the others | Fixed in `76261d0` (T34): such a choice stays on its device |
| 7 | Medium | Words from the Share extension were imported even when already saved | Fixed in `4af8f41`: the import skips them |
| 8 | Medium | Work could write to a word deleted under an open screen | Hardened in `306ee0e`: flashcards, quizzes and "Explain Again" fetch the word again before writing. The crash couldn't be reproduced with an in-memory store, so the tests guard the behavior rather than prove the crash |
| 9 | Low | Switching tabs cancels a podcast being written | Open |
| 10 | Low | "Explain Again" on an object's word rewrote its dictionary form | Fixed in `306ee0e`: object words are named again (no test: app code) |
| 11 | Low | Importing a word list saved once per word | Fixed in `dbf6dbe`: one save at the end, nothing left behind on failure |
| 12 | Low | Mac windows share one navigation state | Open |
| 13 | Low | Today's counts go stale while on screen past midnight | Open |
| 14 | Low | Language state goes stale after adding or removing a language | Open |
| 15 | Low | Very long captured text becomes thousands of views | Open; the context sent with a word is now capped (security 5) |

### Security review

| # | Severity | Finding | Outcome |
| --- | --- | --- | --- |
| 1 | Medium | CSV export allowed formula injection | Fixed in `dbf6dbe`: cells that would run as formulas start with an apostrophe |
| 2 | Medium | The custom endpoint's key wasn't tied to its address, and plain `http` was allowed anywhere | Fixed in `76261d0` (T34): moving a provider to another server removes its key; `http` only on the device and local network |
| 3 | Medium | Keys could land in the HTTP disk cache | Fixed in `d6b6bf3`: provider requests use a session that keeps nothing on disk |
| 4 | Low | Word list import had no size limits | Partly fixed in `dbf6dbe`: files over 10 MB are refused before reading. Per-word field limits are open |
| 5 | Low | No size limits on text sent to providers | Partly fixed in `2ac2ed2`: the context sent with a word is at most 400 characters. Response size is open |
| 6 | Low | Redirects were followed with the key attached | Fixed in `d6b6bf3`: redirects to another server are refused |
| 7 | Low | Signed Mac builds read keys from the login keychain, where any app can write | Fixed in `d6b6bf3`: only unsigned builds fall back to it |
| 8 | Info | The reminder handler accepted any URL | Fixed in `e135ffe`: plan links only |
| 9 | Info | Inbox drafts used default file protection | Fixed in `4af8f41`: complete protection on iOS |
| 10 | Info | UI-test launch options worked in Release | Fixed in `5c980b3` for the in-memory test mode; harmless navigation options remain |
| 11 | Info | The git history contains the author's email | Owner decision: no history rewrite |
| 12 | Info | Shared word lists include the sentences words came from | Open; intended (SPEC C11) |

### Test review

| # | Severity | Finding | Outcome |
| --- | --- | --- | --- |
| 1 | High | The capture language race had no test | Fixed in `2ac2ed2` (code 4) |
| 2 | High | Deleting what an open screen shows was untested | Tests added in `306ee0e` (code 8) |
| 3 | High | UI tests aren't part of `verify.sh` and depend on leftover Simulator state | Partly fixed in `5c980b3`: UI tests no longer import drafts left by earlier runs. They stay a separate gate, since a full run takes 25 minutes on two devices; notification permission isn't reset |
| 4 | High | The accessibility audit's exemptions were too broad | Fixed in `f864d63`: edge exemptions cover only the contrast of fading content, controls are audited, issues without an element are recorded, and contrast is measured against the background. Bar items that stop growing at xxxLarge are allowed by name |
| 5 | High | The "key never in settings" test couldn't fail | Replaced in `f864d63` by a test that saves a real key the way Settings does and searches everything the settings wrote |
| 6 | Medium | Network and failure paths were untested; there is no "switch to the on-device model" action | Partly fixed in `d6b6bf3`: transport errors, time-outs and redirects are tested. The switch action is open |
| 7 | Medium | The translation's language isn't validated | Open |
| 8 | Medium | App-target logic has no unit tests | Open |
| 9 | Medium | Import variants are untested | Partly fixed in `dbf6dbe` (file size); open |
| 10 | Medium | Duplicates from sync aren't handled | Partly fixed in `4af8f41` (inbox); open |
| 11 | Medium | Due counts around midnight are tested only in the scheduler | Open |
| 12 | Medium | The UI tests' AI stub doesn't follow the request | Open |
| 13 | Medium | Not every provider's request was checked | Fixed in `76261d0` (T34): every listed provider |
| 14 | Low | Some assertions are weak | Open |
| 15 | Low | Some tests depend on timing or the OS version | Open |

## SPEC success criteria (Checkpoint 6)

| # | Criterion | Status |
| --- | --- | --- |
| 1 | Onboarding in under a minute on iPhone and Mac | UI test on iPhone and iPad; Mac by hand (owner) |
| 2 | "cookies" with no key, in the app and from the share sheet | Canned answers in UI tests; the real on-device model in the macOS self-test |
| 3 | German routed automatically; one-tap correction | Tests (routing, language race) |
| 4 | A page's sentence across line breaks | Tests on generated pages |
| 5 | An object photo becomes a word | UI test with a typed label; the classifier in the macOS self-test |
| 6 | Scheduling per ADR-007, counts around midnight | Scheduler tests; counts on screen past midnight open (code 13) |
| 7 | A 10-question quiz on device updates reviews | Tests; on device in the macOS self-test |
| 8 | A podcast uses every word and plays on iOS and macOS | Tests and UI test; macOS self-test |
| 9 | A plan's reminder opens its activity | UI tests (quiz and podcast) |
| 10 | Export and import round trip | Tests |
| 11 | Sync between two devices | **Owner, with a signed build** |
| 12 | Traffic only to the chosen provider; keys only in the Keychain | Tests and this review |
| 13 | `verify.sh` passes with no warnings | Passes; it also fails on warnings about our targets now |

## Before a store release

1. Put the Team ID in `Config/Signing.local.xcconfig`, build signed, and deploy the CloudKit schema
   to production.
2. Sync between two devices signed in to the same iCloud account (success criterion 11).
3. Try one key per provider family: an OpenAI-compatible provider and Anthropic. None of the
   providers has been tried with a real key.
4. On a device: the camera, podcasts with the screen locked and with music playing, Now Playing,
   reminders on the Mac, and sharing from Safari on a signed Mac build.
5. Review checkpoints 1 to 5 in `tasks/todo.md` and accept or revise ADR-006 to 008.
