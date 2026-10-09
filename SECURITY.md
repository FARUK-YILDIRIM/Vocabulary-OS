# Security

## Reporting a vulnerability

Please report security problems privately, not in a public issue: use
[**Report a vulnerability**](https://github.com/FARUK-YILDIRIM/Vocabulary-OS/security/advisories/new)
on the repository's Security tab (GitHub private vulnerability reporting). Include the steps to
reproduce, the affected version and what an attacker could gain.

We aim to acknowledge a report within a week. Once the problem is confirmed, we fix it, release the
fix and credit you in the release notes unless you prefer otherwise.

## Supported versions

Only the latest release receives security fixes.

## What the app protects

Vocabulary-OS has no server. Its security rests on these properties, and a report that breaks one is
in scope:

- **API keys** for AI providers are stored only in the Keychain (synchronized through iCloud
  Keychain, accessible when unlocked). They never appear in logs, settings, the SwiftData store, the
  Share extension's inbox or exported files, and they are sent only to their own provider. The key
  of a provider the learner added only ever goes to the server it was entered for: pointing the
  provider at another server removes the key.
- **Network traffic** goes only to the AI provider the learner configured, over HTTPS, and only when
  they use an AI feature. Plain HTTP is allowed only for servers on the learner's own device or
  local network, such as Ollama or LM Studio.
- **Photos** leave the device only when the learner turns on sending object photos to their cloud
  provider, and then only as a small copy without metadata such as the location.
- **Learning data** stays in the learner's private iCloud database and on their devices. It leaves
  only when they export it, and exported word lists contain no review history, photos or keys.
- **Logs** mark user text as private.
- **Opened files and links** are validated before use: a word list file is checked for its format
  and version, and `vocabularyos://` links only start the learner's own study plans.

Out of scope: problems that need a jailbroken device or physical access to an unlocked device, and
the behavior of the AI providers themselves.
