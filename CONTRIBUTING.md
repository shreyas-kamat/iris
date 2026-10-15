# Contributing to Iris

Thank you for wanting to help. Iris is a small project with one maintainer, so a little care up front makes
reviews quick for everyone.

By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md). To report a security problem, see
[`SECURITY.md`](SECURITY.md) and **do not open a public issue**.

## Before you start

- **Bugs:** search the existing issues, then open one with the bug report template. A way to reproduce it,
  your phone and OS version, and the app version make a fix much faster. Please leave out real passwords,
  tokens and server addresses.
- **Features and larger changes:** open an issue first and describe the problem you want solved. Iris has a
  deliberate shape (see below), and it is better to agree on the approach than to discard a finished pull
  request.
- **Small fixes** (typos, an obvious bug with a test) can go straight to a pull request.

## What Iris will and will not do

These are design commitments, not accidents, and a change that breaks one is unlikely to be accepted:

- **Iris talks only to the server the user entered.** No analytics, crash reporting, advertising, relays or
  hosted services, and no new network endpoint.
- **Secrets stay in the platform keystore** and out of the database, preferences, logs and transcripts.
- **No permissions beyond the internet** unless a feature clearly needs one. A new permission also means
  updating the privacy policy and `docs/release.md`.
- **Plain `http` only for private addresses**, and certificates are trusted only by the user's explicit
  choice, per server.
- **The demo never touches the network, the database or secure storage.** Its content uses made-up hosts,
  names and keys only.

## Setting up

You need Flutter 3.41 (Dart 3.11) and, for Android, the Android SDK. The README has the commands:

```sh
flutter pub get
dart run build_runner build      # rerun after editing lib/data/db/database.dart
flutter analyze                  # must report no issues
flutter test
```

Tests in `test/live/` talk to a real Hermes server and are skipped by default. If you run them, they read
connection details from `~/.iris-live.json` outside the repository. Never commit that file, a keystore, or
`android/key.properties`; all are git-ignored, and CI scans for secrets.

## Making a change

1. Branch from `main`.
2. **Write the test first** and watch it fail for the right reason, then make it pass. Bug fixes need a test
   that fails without the fix. Behaviour that is hard to test deserves a sentence in the pull request on how
   you checked it.
3. Keep the change to one concern. Unrelated clean-ups belong in their own pull request.
4. Run `flutter analyze` and `flutter test`; both must pass.
5. **Format only the files you changed:** `dart format path/to/file.dart`. The tree is not uniformly
   formatted, and formatting everything buries a small change in a large diff.
6. Update the docs if behaviour changes, and add a line under **Unreleased** in `CHANGELOG.md` for anything a
   user would notice.

### Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/): `feat(chat): …`, `fix(home): …`,
`docs: …`, `test: …`, `chore: …`. The subject says what changed; the body says why, when it is not obvious.

### Pull requests

Describe what changed, why, and how you checked it (which tests, and whether you ran it on a device or
emulator). For anything visible, include a screenshot in light and dark. Keep drafts as drafts until the
checks are green.

## Code and design guidelines

- **Use the design tokens** in `lib/design/tokens` rather than raw colours, sizes or durations, and the
  existing components (`IrisPressable`, `IrisListRow`, `IrisSheet`, …) rather than new one-offs. The
  reasoning is in [`docs/design-language.md`](docs/design-language.md).
- **Everything must work with reduced motion, large text and a screen reader.** Give anything tappable a
  semantics label and at least a 44-point target.
- **Repositories return `Result<T>` and do not throw.** Wire data goes through the tolerant decoder in
  `lib/core/json.dart`; do not trust a field to exist or have a particular type.
- **Goldens:** the golden images were generated on Windows. If a golden differs only in text rendering on
  your platform, say so rather than regenerating every image. When you change a screen on purpose,
  regenerate only that screen's goldens and open the new images to check them.
- **Specs and plans** for each phase of the app are in [`docs/superpowers/`](docs/superpowers/); they show
  how earlier decisions were made.

## Licence of contributions

Iris is licensed under the [Apache License 2.0](LICENSE). By submitting a contribution you agree, as
section 5 of that licence says, that it is provided under the same terms. There is no separate contributor
agreement.
