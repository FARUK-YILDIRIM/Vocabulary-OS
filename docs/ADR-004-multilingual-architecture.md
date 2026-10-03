# ADR-004: Multiple learning languages with automatic routing

## Status
Accepted (revised 2026-10-04: detection strategy based on measured behavior)

## Date
2026-10-03

## Context
A learner has one native language and may learn several languages at once, for example a Turkish
speaker learning English and German. The owner wants:
- learning languages that can be added at any time;
- each captured word to land in the right language automatically.

Measurements on macOS 26.5 with `NLLanguageRecognizer` limited to `[en, de, tr]`:
- **Full sentences are unambiguous.** "Wir saßen auf einer Bank im Park." scored de = 1.00.
- **Single words are often ambiguous:**

  | Word | Scores |
  | --- | --- |
  | Hand | en 0.45, de 0.40 |
  | Kind | en 0.55, de 0.39 |
  | gift | en 0.49, tr 0.40 |
  | Bank | en 0.83 (even when the user meant German) |

`NLTagger` lemma and lexical-class schemes are available for English, Spanish, French and Turkish
(ran → run, kitapları → kitap). They are **not available for German** on this OS.

## Decision
- **Profile:**
  - One native language and an ordered set of learning languages, stored in the synced settings
    (ADR-002).
  - Removing a learning language hides its words and never deletes them.
- **Every word belongs to exactly one learning language** (a BCP-47 language code). The library,
  review, quizzes and podcasts can be filtered by language, and Today shows counts per language.
- **Detection when a sentence is present:**
  - Run `NLLanguageRecognizer` on the sentence, limited to the learner's learning and native
    languages.
  - Accept the result when the top hypothesis is ≥ 0.80 and it is a learning language.
- **Detection for a lone word or a low-confidence sentence:**
  - Take the recognizer's hypotheses and ask the active AI model for a one-word classification among
    the learner's languages.
  - Show the result as a preselected language chip that the user can change with one tap before
    saving.
- **Not a learning language:** if the detected language is not one the learner studies (for example
  French), the capture UI offers "Add French to my languages". Otherwise the learner picks a language
  from the chips.
- **Lemma and part of speech:**
  - Use `NLTagger` when the scheme is available for the language.
  - Otherwise use the AI model's lemma, for example German.
  - The learner can always edit both.
- **Native language:** explanations, translations, quiz questions and podcast glosses use the native
  language that is current at generation time. That language is stored on the word, so a later change
  in settings does not corrupt existing content.

## Alternatives Considered
- **Ask the LLM for every detection:**
  - Slower (one more round trip) and needs AI even for unambiguous sentences.
  - Rejected: the recognizer handles sentences perfectly and offline.
- **Always ask the user to choose the language:**
  - Too much friction for the common case.
  - Rejected; kept only as the confirm/override chip.
- **One mixed pool without language ownership:**
  - Quizzes would mix languages and TTS voices would be wrong.
  - Rejected.

## Consequences
- Common sentence captures need no interaction and work offline.
- Single-word captures show a language chip. It is correct most of the time and fixable with one tap.
- German lemmas depend on the AI model and can be wrong more often. The learner can edit them.
- Adding a language later is a settings change only; no data migration is needed.

## Sources
- `NLLanguageRecognizer`: https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer
- `NLTagger` lemma scheme: https://developer.apple.com/documentation/naturallanguage/nltagscheme/lemma
- Measurements: local probe on macOS 26.5.2, recorded in the 2026-10-04 planning session (also
  reproduced by `VocabularyCoreTests`).
