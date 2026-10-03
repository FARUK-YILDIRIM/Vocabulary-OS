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
  - On device, longer scripts are generated in sections that each fit the context window. Cloud
    models generate the script in one call.
- **Storage:** scripts are stored as `PodcastEpisode` records (JSON segments) and sync like other
  data. No audio files are stored or synced.
- **Playback:**
  - Live `AVSpeechSynthesizer` playback, one utterance per segment. A dialogue uses two distinct
    installed voices for the language; when only one voice exists, the second speaker uses a
    different pitch.
  - Controls: play/pause, previous/next segment, speed (0.8×–1.2×).
  - The transcript highlights the current segment and the target words.
- **Voices:**
  - Use the best installed quality for the language.
  - If none is installed, the player explains how to download a voice in system settings and falls
    back to the default voice.

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
