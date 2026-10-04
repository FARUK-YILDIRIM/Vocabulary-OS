# ADR-008: Podcasts as AI scripts spoken with on-device voices

## Status
Proposed

## Date
2026-10-04

## Context
The owner wants AI-generated podcasts that reinforce saved words. Constraints:
- no server;
- privacy;
- users bring their own AI key, which may be for a provider with no text-to-speech;
- sync through iCloud;
- the on-device model's 4,096-token context.

Measurements and facts:
- `AVSpeechSynthesizer` is available on iOS and macOS 26.
- This Mac has voices for tr-TR (Yelda), de-DE (Anna) and en-US (Samantha).
- `write(_:toBufferCallback:)` can render speech to `AVAudioPCMBuffer`s. The end is signalled by
  zero-length buffers, which can arrive twice.

## Decision
- **Script generation:**
  - The AI produces a structured script: a title and a list of segments, each with a speaker
    (`host`, `guest` or `narrator`) and text, plus a short glossary of the target words.
  - It uses the chosen words, level (A1–C2), length and style (dialogue or story).
  - The script is validated: every target word or an inflection appears, segments are not empty,
    and lengths are capped.
  - Cloud models generate the script in one call.
  - On device, measured with `vos-eval podcast` (docs/eval/podcast-on-device.md), the script is
    drafted and then completed:
    - The draft is written in short parts, about one per word (2–6 parts for about two minutes,
      4–10 for about five), with sampling: greedy decoding repeated sentences.
    - Asked to use words in a dialogue, the model often left them out, even with one word per part.
      So each word the draft left out gets one more short line of its own. The model writes one
      sentence with a given word reliably. The line is validated and added to that word's part.
    - Earlier lines are not quoted in the prompt, because the model then repeated them. Sentences said
      before are dropped and an over-long part loses its last lines, rather than failing the part.
    - The first part sees every word, to choose a topic where they all fit.
    - First version: 0 of 3 scripts valid. This design: 9 of 9 valid over three runs.
- **Storage:** scripts are stored as `PodcastEpisode` records (JSON segments) and sync like other
  data. No audio files are stored or synced.
- **Playback:**
  - Live `AVSpeechSynthesizer` playback, one utterance per segment. A dialogue uses two distinct
    installed voices for the language; when only one voice exists, the second speaker uses a
    different pitch.
  - Controls: play/pause, previous/next segment, speed (0.8×–1.2×).
  - The transcript highlights the current segment and the target words.
- **Voices:**
  - Use the best installed quality for the language (premium, then enhanced, then default), then the
    region the language is usually heard in (en-US, pt-BR; zh-TW for Traditional Chinese).
  - Novelty and personal voices are never used. macOS also ships robotic-sounding voices (Eddy,
    Flo, Grandma …) at default quality without a gender; regular voices with a gender come first,
    and a dialogue's second voice is only ever a regular one.
  - If none is installed, the player explains how to download a voice in system settings and falls
    back to the default voice.
  - Speech plays in the `.playback` audio session on iPhone and iPad, so a listen button works with
    the ringer off.
  - The same player speaks single words (word detail, listening quiz questions).

## Alternatives Considered
- **Cloud TTS (e.g. OpenAI audio):**
  - Nicer voices, but only some providers offer it.
  - Costs the user money, uploads text and produces large audio files to store or sync.
  - Rejected for v1. It can be an optional provider capability later.
- **Pre-rendered audio files synced through CloudKit:**
  - Storage-heavy and redundant, since every device can speak the script.
  - Rejected. Exporting an episode to an audio file with `write(_:toBufferCallback:)` is a possible
    v1.1 feature.

## Consequences
- Podcasts work offline once the script exists, cost nothing to play and never upload audio.
- Voice quality depends on the voices installed on the device and is lower than cloud TTS.
- Background playback on iOS needs the audio background mode and an active audio session. This is
  handled in the podcast task.

## Sources
- `AVSpeechSynthesizer`: https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer
- `write(_:toBufferCallback:)`:
  https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:)
- Voice quality and downloads:
  https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality
- Context window: https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window
