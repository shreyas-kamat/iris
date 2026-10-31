# Local validation — 21 October 2026

Release candidate: **Iris 1.0.0 (1)**, bundle ID `com.iflotech.iris`.
Local tools: Flutter **3.44.8** / Dart **3.12.2**, Xcode **26.3**, iOS SDK **26.2**.
CI remains pinned to Flutter **3.41.6**; its Windows golden run must be checked before submission.

## Passed

- `flutter analyze --no-pub`: no issues after the final Dart/test changes.
- 126 targeted widget tests: consent accept/cancel/dismiss, voice entry and screens, voice settings,
  chat, busy settings and general settings.
- The complete non-golden run finished with 1,444 passing tests, 9 explicitly skipped live tests
  and one timing-sensitive failure in `connect_screen_test.dart` (LAN address). The test assumed
  a request completed within 100 ms. After replacing that assumption with a bounded wait for the
  actual request, all 8 tests in that file passed. The whole suite was not repeated after this
  test-only change.
- Plist and Xcode project syntax; Podfile Ruby syntax; launch storyboard XML; `git diff --check`.
- Store copy fits Apple's name, subtitle, keywords, promotional text and description limits.
- Default App Store icon: 1024 × 1024, opaque. Dark/tinted variants are present.
- An unsigned release archive compiled successfully. Inspected app settings: iOS deployment
  target 14.0, `iphoneos26.2`, arm64 executable, expected ID/version/build, encryption declaration
  and updated microphone description. The launch screen was then replaced to remove Flutter's
  placeholder warning; final rebuild results are recorded below.
- The inspected archive contains the app manifest and bundled SDK privacy manifests, including
  Flutter, WebRTC, permission_handler, shared_preferences, file_picker and secure storage.
  All parsed successfully. Required-reason declarations are present in the SDK manifests where
  declared (timestamps, boot time and user defaults); no inspected manifest declares tracking.
  Organizer's distribution validation/privacy report is still required.

## Not a clean golden run

The initial full suite reported 1,437 passes, 66 failures and 9 skips. The local failure directory
contains 63 golden-image comparisons. A sampled gallery diff shows text rendering differences;
the baselines were produced on Windows with the older pinned Flutter. This does not establish
that every image difference is harmless. Baselines were preserved. Review the Windows CI results
and expected Settings/permission copy changes before release. The subsequent functional run is
reported separately above; the initial run must not be described as passing.

## Still required

- Select the seller's Apple Developer Team and configure distribution signing/provisioning.
  Only an Apple Development identity was found locally; no Team ID was guessed. There is no
  signed IPA and nothing has been uploaded or submitted to App Store Connect.
- Real iPhone/iPad TestFlight checks, actual store screenshots, review server and credentials,
  age rating and App Privacy answers. See `README.md` in this directory.
- Verify/publish the updated website privacy policy. A HEAD request returned HTTP 200, but
  current deployed policy contents were not verified. The local policy was corrected to explain
  direct GPT-Live audio and consent. Its website build was not run: `npm` is unavailable on this Mac.
- Two existing audio plugins still use CocoaPods rather than Swift Package Manager; the current
  toolchain builds them via the fallback. Future Flutter toolchain upgrades need a new release check.

## Artifacts

- Archive: `build/ios/archive/Runner.xcarchive` (unsigned; do not upload as a signed distribution).
- App Store export options: `ios/ExportOptions-AppStore.plist`.
- Listing and review instructions: `store/app-store/README.md` and `en-US/`.
- Validation logs are retained locally in `build/release-validation/`.

## Final archive rebuild

`flutter build ipa --release --no-codesign --no-pub` completed successfully after the launch
screen change (203 seconds). Flutter reported passing app settings validation and no remaining
launch-placeholder warning. The final archive is 212.1 MB, retains version 1.0.0 (1), and was
rechecked for its bundle ID, SDK, microphone string, compiled launch storyboard and all 12
privacy manifests. No signed IPA was generated.
