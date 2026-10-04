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
    (`host`, `guest` or `narrator`) and text. The player lists the target words with their saved
    translations, so the model writes no glossary.
  - It uses the chosen words, level (A1–C2), length and style (dialogue or story).
  - The script is validated: every target word or an inflection appears, segments are not empty,
    and lengths are capped.
  - Cloud models generate the script in one call.
  - On device, measured with `vos-eval podcast` (docs/eval/podcast-on-device.md), the script is
    drafted and then completed:
    - The draft is written in parts of 3 to 5 short lines, about 40 words each: enough parts for
      the length and at least one per word (6 for about two minutes, 14 for about five), with
      sampling: greedy decoding repeated sentences. With only a part per word, a few words made an
      episode of about a minute (131–222 words in the eval against a 260-word target); now 303–335
      words for dialogues and 159–312 for stories, in 17–30 s. Parts after the words' parts have no
      word of their own, and they drift further from the topic.
    - A part the model's safety rules stop is left out, and its words get lines of their own: in one
      run, a part about banking stopped a whole episode.
    - Asked to use words in a dialogue, the model often left them out, even with one word per part.
      So each word the draft left out gets one more short line of its own. The model writes one
      sentence with a given word reliably. The line is validated and added to that word's part.
    - Earlier lines are not quoted in the prompt, because the model then repeated them. Sentences said
      before are dropped and an over-long part loses its last lines, rather than failing the part.
    - The first part sees every word, to choose a topic where they all fit.
    - First version: 0 of 3 scripts valid. This design: 9 of 9 valid over three runs, and 6 of 6
      over two runs with the longer drafts.
    - A title in another language is asked for again; the model sometimes titled a German episode
      in English.
- **Storage:** scripts are stored as `PodcastEpisode` records (JSON segments) and sync like other
  data. No audio files are stored or synced.
- **Playback:**
  - Live `AVSpeechSynthesizer` playback, one utterance per segment. A dialogue uses two distinct
    installed voices for the language; when only one voice exists, the second speaker uses a
    different pitch.
  - Controls: play/pause, previous/next segment, speed (0.8×–1.2×). On a Mac, Space plays or pauses
    and ⌘← / ⌘→ skip.
  - The transcript highlights the current segment and the target words. The words are found in any
    form, the same way validation counts them (`WordOccurrences`), and tapping one pauses the episode
    for the word's detail; it continues when the detail closes.
  - Leaving the player stops it and remembers the segment (`resumeSegment`, saved as each segment
    starts). The next visit continues there; an episode played to its end starts over.
  - On iPhone and iPad an episode keeps playing while the screen is locked (`UIBackgroundModes`
    `audio`). Like other podcast apps, an episode pauses other audio, which makes it the Now Playing
    app: the lock screen and Control Center show its title with play/pause and previous/next line.
    A listen button only lowers other audio, since a word takes a second.
- **Voices:**
  - Use the best installed quality for the language (premium, then enhanced, then default), then the
    region the language is usually heard in (en-US, pt-BR; zh-TW for Traditional Chinese).
  - Novelty and personal voices are never used. macOS also ships robotic-sounding voices at default
    quality: the Eloquence voices (Eddy, Flo, Grandma …), which have no gender, and the old MacinTalk
    voices (Fred, Ralph …), whose identifiers start with `com.apple.speech.synthesis.voice.`. Regular
    voices come first, and a dialogue's second voice is only ever a regular one. Measured on this
    Mac: before MacinTalk voices were recognized, Fred (male) beat Samantha by name for English.
  - If none is installed, the player explains how to download a voice in system settings and falls
    back to the default voice. A dialogue with one installed voice also says so: the guest then
    speaks with the host's voice at a lower pitch.
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
- Background playback on iOS needs the audio background mode and an active audio session: the app
  declares `audio` in `UIBackgroundModes`, and speech plays in the `.playback` session.

## Sources
- `AVSpeechSynthesizer`: https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer
- `write(_:toBufferCallback:)`:
  https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:)
- Voice quality and downloads:
  https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality
- Context window: https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window
