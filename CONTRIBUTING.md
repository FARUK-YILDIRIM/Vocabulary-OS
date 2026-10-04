# Contributing to Vocabulary-OS

Thank you for helping. This guide covers setting up, making a change and getting it merged. The
rules here are the same ones the AI coding agents follow in [`CLAUDE.md`](CLAUDE.md); that file has
the details.

## Set up

1. Install Xcode 26.2 or newer on macOS 26, and XcodeGen: `brew install xcodegen`.
2. Clone the repository and generate the project:

   ```bash
   xcodegen generate
   open VocabularyOS.xcodeproj
   ```

3. Run the **VocabularyOS** scheme on a simulator or on "My Mac". No Apple Developer account is
   needed: unsigned builds keep data on the device. See the README for building with your own team.

Never edit `VocabularyOS.xcodeproj`: it is generated from `project.yml` and not committed.

## Make a change

- **Start from the spec.** [`SPEC.md`](SPEC.md) says what the app does, and the ADRs in
  [`docs/`](docs) say why it is built this way. A change to either goes in the same pull request
  as the code.
- **Test first.** New behavior gets a test that fails before the change: Swift Testing in
  `Packages/VocabularyKit/Tests`, XCUITest in `UITests` for flows across screens.
- **Keep logic in the package.** `VocabularyKit` holds the logic and is tested on the Mac host; the
  app target wires screens to it.
- **Translate every string.** The app ships in English and Turkish. `scripts/verify.sh` adds new
  strings to the String Catalogs and fails until each has a Turkish translation. If you don't speak
  Turkish, say so in the pull request and a maintainer will translate.
- **Respect the boundaries.** No server, analytics or tracking. API keys live only in the Keychain.
  Ask in an issue first before adding a dependency, a new AI provider, sending a new kind of data to
  providers, or changing the minimum OS, the schema after release, signing or entitlements.

## Check it

```bash
scripts/verify.sh       # project, package tests, iOS and macOS builds, String Catalogs
scripts/ui-test.sh      # UI tests on iPhone 17; VOS_UI_TEST_DEVICE="iPad Pro 13-inch (M5)" for iPad
scripts/mac-smoke.sh    # the macOS build launches and logs no errors
```

`scripts/verify.sh` must pass with no warnings in project code or about its targets. Changes to screens should also pass
the UI tests on an iPhone and an iPad simulator; look at the screenshots they export to
`.build/ui-tests/screenshots`. Prompt changes are measured with
`swift run --package-path Packages/VocabularyKit vos-eval insight|quiz|podcast` before and after.

## Commit and open a pull request

- One logical change per commit, in English: `<type>(<scope>): <imperative summary>`, then a body
  that explains why. Types: feat, fix, refactor, test, docs, chore, build, ci. Scopes are listed in
  `CLAUDE.md`.
- Stage files by name and look at the staged diff before committing: never commit secrets, a Team
  ID, `Config/Signing.local.xcconfig` or personal data.
- Note anything you noticed but left alone under "Noticed, not touched" in the commit body.
- In the pull request, say what you changed, how you checked it, and include screenshots for screen
  changes.

## License

By contributing, you agree that your contribution is licensed under the project's
[MIT License](LICENSE).

## Report a problem

Open an issue with the steps to reproduce, what you expected and what happened, and your device and
OS version. Report security problems privately as described in [`SECURITY.md`](SECURITY.md).
