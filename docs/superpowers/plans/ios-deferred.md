# iOS deferred tasks

Everything that needs the Mac (or an iPhone) and was put off. The `/ios` command runs this list in one go on the Mac.
Add an item whenever iOS work is deferred; tick it and note the result when done. Never put secrets here.

Minimum model: **Sonnet** for the build and device steps; **Opus** for any Swift fix that changes design.

## Setup (the Mac, once)

- `git fetch && git checkout <branch named in the item>`; Xcode installed; iPhone paired and in developer mode.
- `flutter pub get && (cd ios && pod install)`.

## Items

### I1 — Swift compile of push (from PS5 Task 10) — todo
- Branch: `feat/push`. Files never compiled: `ios/Runner/AppDelegate.swift` (`IrisPushPlugin`), `ios/Runner/Runner.entitlements`,
  `ios/Runner.xcodeproj/project.pbxproj` (entitlements on Debug, Release, Profile).
- Run `flutter build ios --no-codesign`. Fix any Swift error test-first where Dart is involved; commit each fix.
- Check in Xcode that the Push Notifications capability is on the Runner target with the team's signing.
- Done when the build succeeds.

### I2 — Push device pass on the iPhone (from PS6 Task 11, Step 3) — todo
- Needs: plugin on the server with `<iris root>/push/apns.json` and the key placed by the user (`GET push/status` shows
  `apns_configured: true`); the Iris plugin installed (see I3 if the installer exists); a build on the iPhone.
- Check: notification permission prompt; register (Settings -> Notifications -> test notification arrives); reply
  notice in the user's text while the app is closed; approval notice with Approve once / Deny asking for unlock, opening
  the chat and "Approved once."; a cron job notice; the open chat is not notified; a `text`-mode event shows no content
  on the lock screen; a tap from a cold start opens the chat.
- Screenshots (no private content) go to `docs/superpowers/plans/2026-11-13-push-device/`. Log results and defects in
  the Phase 9 progress log; fix defects test-first.

## Order

I1, then I2. Items added later go after these.
