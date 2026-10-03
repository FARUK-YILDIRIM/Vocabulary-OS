# ADR-002: Private iCloud data, extension hand-off, and file-based sharing

## Status
Accepted (revised 2026-10-04: storage details and the sharing mechanism were researched and decided;
how the Share extension reads settings was added with the extension)

## Date
2026-10-03

## Context
Requirements from the owner:
- No server.
- All data stays private in the user's iCloud and syncs across their devices.
- The user can share words if they choose to. The owner asked for the sharing mechanism to be
  researched in Apple's documentation.

Data comes in four kinds:
- **Learning data:** words, lists, review logs, plans, quiz results, podcast scripts. This is
  relational, grows over time, and must sync.
- **Settings:** native and learning languages, the selected provider and model. These are small and
  must sync.
- **Secrets:** API keys. They must sync, must never be stored in plain form, and must never be
  exported.
- **Hand-off:** captures from the Share extension, which runs in a separate process.

The first version of this ADR assumed SwiftData supports CloudKit sharing through
`.cloudKitContainer(identifier:)`. That API does not exist, and SwiftData does not support sharing.

## Decision
1. **Learning data: SwiftData with the CloudKit private database.**
   - Use `ModelConfiguration(cloudKitDatabase: .automatic)`. It syncs with the first iCloud container
     in the app's entitlements, and stays local-only when there is none. This keeps unsigned
     contributor builds working.
   - The store stays in the app's own container: `groupContainer: .none`.
   - Models follow the CloudKit rules: no `.unique` attributes, every property optional or defaulted,
     every relationship optional with an inverse, no `.deny` delete rule, no ordered relationships.
   - Identity is a `UUID` attribute, because CloudKit cannot enforce uniqueness. Duplicates are
     resolved in app logic.
   - Required capabilities: iCloud with CloudKit, Background Modes → Remote notifications, and the
     push entitlement (`aps-environment` on iOS, `com.apple.developer.aps-environment` on macOS).
   - The CloudKit schema is initialized in development and deployed to production by hand in the
     CloudKit Console before each release. The production schema is additive-only, so model changes
     after v1 must only add things.
2. **Settings: `NSUbiquitousKeyValueStore`, mirrored to `UserDefaults`.**
   - The store has a 1 MB / 1,024-key limit. It is meant for preferences and is not for sensitive
     data.
   - Changes from other devices arrive through `didChangeExternallyNotification`.
   - It only syncs in App Store/TestFlight-signed builds, so the `UserDefaults` mirror is what
     contributor builds use.
   - On iOS the mirror is the App Group's `UserDefaults` suite, so the Share extension can read the
     profile and the AI selection. Reading a value copies the iCloud value into the mirror, so the
     mirror is never older than what the app last read.
   - Only the app writes settings. A value the extension wrote would never reach iCloud and would be
     overwritten at the app's next launch, so the extension cannot add a learning language.
3. **Secrets: Keychain generic passwords.**
   - Attributes: `kSecAttrSynchronizable = true` (iCloud Keychain), `kSecAttrAccessibleWhenUnlocked`,
     and `kSecUseDataProtectionKeychain = true` on macOS.
   - The access group is the App Group, so the Share extension can read the keys.
   - Keys never touch SwiftData, `UserDefaults`, logs or export files.
4. **Share extension hand-off: an inbox in the App Group container.**
   - The extension never opens the synced store and has no CloudKit entitlement.
   - It writes each saved capture as a small JSON file to `<AppGroup>/Inbox/`. The app imports and
     deletes inbox files whenever it becomes active.
   - Each capture is its own atomically written file, so a broken write loses only that capture.
     Unreadable files are deleted and logged. A capture that fails to import stays for the next
     activation.
   - The extension reads settings from the mirror (decision 2) and API keys from the App Group
     keychain access group, so it explains words with the same provider as the app.
   - Apple's guidance: the app should be the only process that syncs. When an app and an extension
     both sync the same store, the result is error 134410.
5. **Sharing in v1: export/import files.**
   - A word list or a language's words exports as a versioned `.vocabularyos` JSON document through
     `ShareLink`/the share sheet. Opening it imports the words, skipping duplicates by lemma and
     language.
   - CSV export covers spreadsheets and Anki.
   - Nothing leaves the device unless the user exports it. Review history and keys are never
     exported.

## Alternatives Considered
- **CloudKit sharing (`CKShare`) for collaborative lists:**
  - SwiftData does not support CloudKit shared or public databases. Apple DTS confirmed this in 2024,
    and nothing changed in the 26.x releases.
  - Apple recommends `NSPersistentCloudKitContainer` (Core Data) for sharing object graphs. That would
    mean moving private sync to Core Data as well.
  - Rejected for v1 because of the cost. Possible later via a separate Core Data stack or raw
    `CKShare` for simple records.
- **CloudKit public database:**
  - Anyone with the record IDs could read shared lists, and it would need moderation.
  - Rejected: it conflicts with "private by default".
- **Extension writes directly to the synced store (with or without CloudKit):**
  - Apple engineers advise against giving extensions sync responsibility.
  - SQLite locks in a group container risk `0xdead10cc` terminations.
  - Rejected in favor of the inbox.
- **Settings in SwiftData:**
  - Singleton records duplicate under CloudKit merge.
  - Rejected: the key-value store fits small preferences.

## Consequences
- Sync is free, private and needs no backend. It works offline and catches up when online.
- Words saved in the Share extension appear on other devices only after the app has been opened
  once.
- Any schema change after release needs care. Additive changes are fine; removing or renaming needs
  a migration plan and asking first (see SPEC Boundaries).
- Real sync can only be tested with a signed build and an iCloud account. Unit tests use in-memory
  stores.
- Sharing is one-way, as copies. There is no live collaboration in v1.

## Sources
- Syncing model data across a person's devices:
  https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices
- `ModelConfiguration.CloudKitDatabase` (`.automatic` / `.private(_:)` / `.none`):
  https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct
- CloudKit model rules (Core Data):
  https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit
- Debugging sync, error 134410, unsupported ordered relationships:
  https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer
- Optional/default attribute requirement (Apple engineer): https://developer.apple.com/forums/thread/739351
- Deploying the schema:
  https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema
- SwiftData does not support CloudKit sharing (Apple DTS): https://developer.apple.com/forums/thread/765776 ,
  https://developer.apple.com/forums/thread/756721
- Core Data sharing sample:
  https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users
- Extensions and sync ownership: https://developer.apple.com/forums/thread/762093 ;
  WWDC26 SwiftData group lab https://developer.apple.com/videos/play/wwdc2026/8017/
- `NSUbiquitousKeyValueStore` limits and notification:
  https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore
- Keychain sync and sharing:
  https://developer.apple.com/documentation/security/ksecattrsynchronizable ,
  https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps ,
  https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain ,
  https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains
