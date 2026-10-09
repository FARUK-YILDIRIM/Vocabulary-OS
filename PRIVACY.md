# Privacy Policy

Effective 9 October 2026.

Vocabulary-OS is a free, open-source vocabulary app for iPhone, iPad and Mac, developed by Faruk
Yildirim. This policy explains what happens to your data when you use it.

## In short

- **We collect no data.** The app has no account, no server of ours, no analytics, no advertising
  and no tracking. We can't see your words or anything else you do in the app.
- **Your words stay with you:** on your devices and in your private iCloud.
- **AI requests go only where you choose.** By default, Apple's on-device model explains words and
  nothing leaves your device. If you connect a cloud AI provider with your own API key, the app
  tells you what it sends before the first request.

## Your words and settings

Your words, their meanings, the sentences they came from, review progress, lists, study plans,
quiz results, podcast scripts and settings are stored on your device. If you're signed in to
iCloud, they sync through your private iCloud database and iCloud key-value storage, which Apple
operates under [its privacy policy](https://www.apple.com/legal/privacy/). We have no access to
them.

## AI providers

- **On-device model (the default):** Apple Intelligence runs on your device. Nothing is sent
  anywhere.
- **Cloud providers you connect:** if you add your own API key for a provider such as OpenAI,
  Anthropic, Google Gemini or DeepSeek, or a server of your own, the app sends requests directly
  from your device to that provider:
  - To explain a word: the word, the sentence it came from (at most 400 characters) and the names of
    your languages.
  - For quizzes and podcasts: the words you choose and their meanings.
  - Object photos only if you turn on "Send object photos", as a smaller copy without metadata such
    as the location.

  That provider's own privacy policy applies to what it receives. The app asks you before its first
  request to a cloud provider. It never sends your data to any other server and never switches
  providers on its own.
- **API keys** are stored in your Keychain, which can sync through iCloud Keychain. They are sent
  only to their own provider.

## Camera, photos, speech and notifications

- The camera, your photo library and files are used only when you choose a photo. Text recognition
  and object recognition run on your device.
- Words and podcasts are spoken with your device's voices; no audio is uploaded.
- Study plan reminders are scheduled on your device.
- Words you save from the share sheet wait in a folder on your device until the app imports them.

## Sharing and deleting

- An exported word list contains your words with their meanings and sentences. It has no review
  history, photos or keys. You decide where it goes.
- You can delete words in the app at any time. Deleting the app removes its data from the device,
  except API keys in the Keychain: remove them in the app's AI settings first. To remove the copy in
  iCloud, open iCloud storage settings and delete the Vocabulary-OS data.

## Children

The app collects no data from anyone, including children.

## Changes and contact

Changes to this policy are published here, with a new effective date, and the history of the file
shows every earlier version. For questions, open an issue at
[github.com/FARUK-YILDIRIM/Vocabulary-OS](https://github.com/FARUK-YILDIRIM/Vocabulary-OS/issues).
Report security problems privately, as described in [SECURITY.md](SECURITY.md).
