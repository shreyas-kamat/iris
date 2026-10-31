# Releasing Iris

Application ID (Android) and bundle ID (iOS): **`com.iflotech.iris`**. Both are permanent once the
first build is uploaded.

## Android upload key (once)

Generate the key outside the repository and keep a backup somewhere safe. Losing it means going
through Google's upload-key reset.

One line, in **PowerShell**:

```
keytool -genkeypair -v -keystore "$env:USERPROFILE\iris-upload.jks" -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

In **Git Bash**, use `"$USERPROFILE/iris-upload.jks"` for the path. In the old `cmd.exe` it is
`%USERPROFILE%\iris-upload.jks`; that form is taken literally anywhere else and fails with
"path not found". keytool asks for a password and for your name and organisation. The password
protects the key, so pick a strong one and store it in a password manager with the file.

Create `android/key.properties` (git-ignored, as are `*.jks` and `*.keystore`):

```
storeFile=C:/Users/<you>/iris-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

`storeFile` may be absolute or relative to `android/`. Without `key.properties`, a release build
falls back to the debug key so `flutter run --release` still works, but Google Play rejects it.

## Build

```
flutter build appbundle --release      # Play Console: upload build/app/outputs/bundle/release/app-release.aab
flutter build apk --release            # sideloading and emulator checks
```

Raise the build number in `pubspec.yaml` (`version: 1.0.0+N`) for every upload; Play needs a new
`+N` each time.

Use Play App Signing when asked. Google then holds the app-signing key and the key above is only
the upload key.

## Store listing assets

- `store/play-icon-512.png`: the Play Console app icon (512 x 512, opaque).
- The App Store icon is in `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (1024 x 1024, with
  dark and tinted variants for iOS 18).

## iOS

The app supports iPhone and iPad, with a minimum deployment target of iOS 14.
Use Xcode 26 or later and an iOS 26 SDK or later for App Store uploads (Apple's requirement
since 28 April 2026). The deployment target is separate from the SDK used to build it.

### Validate locally

```sh
flutter pub get
flutter analyze
flutter test                         # golden baselines are Windows; review Mac rendering differences
flutter build ipa --release --no-codesign
```

The last command creates `build/ios/archive/Runner.xcarchive` without signing; it does **not**
create an uploadable IPA. CI also compiles this unsigned release archive.

### Sign and export

1. Enrol the seller in the Apple Developer Program, accept current agreements, and register the
   explicit bundle ID `com.iflotech.iris`. The privacy policy currently identifies the App Store
   seller as Daturo Solutions Pvt Ltd; confirm that this matches the signing organization.
2. Open `ios/Runner.xcworkspace` in Xcode. Add the developer account in Xcode Settings, then select
   the seller's Team under Runner → Signing & Capabilities for **all** configurations. Keep
   automatic signing enabled. Do not use a guessed Team ID or commit signing credentials.
3. Create the app record in App Store Connect with that bundle ID. Choose its SKU there.
4. Increment the `+N` in `pubspec.yaml` for each upload (including TestFlight). The first local
   release candidate remains `1.0.0+1`; check whether build 1 has already been uploaded.
5. Build the signed distribution export:

   ```sh
   flutter build ipa --release --export-options-plist=ios/ExportOptions-AppStore.plist
   ```

6. In Xcode Organizer, validate the archive and inspect its privacy report. Upload the signed
   export through Organizer or Transporter. Keep the archive and dSYMs for symbolication.

`ios/ExportOptions-AppStore.plist` exports for App Store Connect using automatic signing and
preserves the explicit build number. A development identity alone does not prove distribution
signing is ready. Xcode must be able to create or access the seller's distribution certificate
and provisioning profile. Do not submit the unsigned archive.

### App Store Connect and device checks

The listing draft, review instructions and outstanding release gates are in
[`../store/app-store/README.md`](../store/app-store/README.md). Complete them before submitting.

Test the **signed release** on a physical iPhone and iPad through TestFlight: microphone
permission granted/denied, dictation, files/photos, local-network permission and a private HTTP
server, HTTPS authentication, voice background playback/recording, interruptions, Bluetooth,
earpiece/speaker routing, and GPT-Live consent/cancellation. Simulator audio cannot establish
that these work on a device. Confirm permission_handler is built with `PERMISSION_MICROPHONE=1`
(the Podfile enables it for CocoaPods; the Swift package reads the microphone usage key in Info.plist). Never regenerate Windows golden baselines just to suppress Mac diffs.

Apple references (checked 21 October 2026):
- https://developer.apple.com/news/upcoming-requirements/?id=04282026a
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/app-store/app-privacy-details/

## Permissions the store forms must match

- **Internet.** To reach the user's own Hermes server.
- **Local network (iOS).** To reach a server on the same Wi-Fi or tailnet.
- **Microphone.** Only when the person taps the mic to dictate; the clip goes to their own server for
  speech-to-text and is not kept. Android declares `RECORD_AUDIO`; iOS has a microphone usage string.
- **Photos and files.** Chosen through the system picker, so Android needs no storage permission; iOS has a
  photo library usage string.
- Nothing else: no camera, location or contacts. Notifications only for an ongoing voice call's own notification. QR pairing was dropped
  for 1.0 because no screen used it; if it returns, the camera permission and its usage string come
  back with it, along with the privacy policy and support wording.

Phase 6 adds none: deleting, pinning, branching and the prompts use the existing network permission only.

## Phase 8: voice

- **Android permissions added:** `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MICROPHONE` (a call keeps running
  in the background), `POST_NOTIFICATIONS` (the call's notification, asked once), `WAKE_LOCK` (the call screen
  keeps the screen on), `MODIFY_AUDIO_SETTINGS` (the speaker and earpiece), and `BLUETOOTH_CONNECT` (headsets).
  `RECEIVE_BOOT_COMPLETED` from the foreground-service plugin is removed: a call never restarts after a reboot.
- **iOS:** the `audio` background mode. The microphone usage string already exists. `permission_handler` needs
  `PERMISSION_MICROPHONE=1` in the Podfile's `GCC_PREPROCESSOR_DEFINITIONS`, or it reports the microphone as
  denied; the Podfile now enables it.
- **Data safety:** audio. Voice and dictation clips go to the user's own server and are not collected or stored
  by Iris. For GPT-Live calls, the audio goes from the phone to OpenAI; the work and history stay on the server.
- **Privacy policy:** the voice paragraphs in `site-src/src/pages/Privacy.tsx` (effective 19 October 2026).
- Still to check on a device (Phase 8 Task 18): earpiece routing, echo cancellation during playback, the iOS
  audio session after playback setup, and `flutter_webrtc` with the audio route for GPT-Live.

