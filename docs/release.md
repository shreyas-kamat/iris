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

Iris has not been built for iOS yet; every device check so far was on an Android emulator. It
needs a Mac or a cloud build service, and an Apple Developer account, to build, sign and upload.
The project is set up for it: bundle ID, icons, `ITSAppUsesNonExemptEncryption = false` (the app
only uses standard HTTPS), a Local Network usage string, and `PrivacyInfo.xcprivacy` (no tracking
and no data collected).

## Permissions the store forms must match

- **Internet.** To reach the user's own Hermes server.
- **Local network (iOS).** To reach a server on the same Wi-Fi or tailnet.
- **Microphone.** Only when the person taps the mic to dictate; the clip goes to their own server for
  speech-to-text and is not kept. Android declares `RECORD_AUDIO`; iOS has a microphone usage string.
- **Photos and files.** Chosen through the system picker, so Android needs no storage permission; iOS has a
  photo library usage string.
- Nothing else: no camera, location, contacts or notifications. QR pairing was dropped
  for 1.0 because no screen used it; if it returns, the camera permission and its usage string come
  back with it, along with the privacy policy and support wording.
