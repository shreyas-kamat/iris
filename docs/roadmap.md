# Roadmap

Work deliberately left out of earlier phases, to be picked up in a later phase.

## Camera photo upload

Let the user take a photo from the "+" attachment menu and send it with a message, alongside the existing
Photos and Files rows.

**Why it is not in 1.0:** Phase 5 and Phase 6 both scoped camera capture out
(`docs/superpowers/specs/2026-10-15-phase5-design.md`, `docs/superpowers/specs/2026-10-16-phase6-design.md`).
Attachments use `file_picker` only, which needs no camera permission. The 1.0 App Store build carries a
placeholder `NSCameraUsageDescription` only because the WebRTC library (`flutter_webrtc`) references camera
APIs; Iris itself never opens the camera.

**What it will take:**
- A capture path, such as the `image_picker` plugin with `ImageSource.camera`, or `camera` for a custom viewfinder.
- A "Camera" row in the "+" menu in `lib/features/chat/attachment_picker.dart`, plus a size limit (Phase 6 sketched
  25 MB; today the limit is 20 MB).
- A just-in-time permission sheet, following `lib/features/voice/mic_permission_sheet.dart`.
- Rewrite `NSCameraUsageDescription` in `ios/Runner/Info.plist` to describe real use, and add the Android
  `CAMERA` permission.
- Update the privacy policy (`site-src/src/pages/Privacy.tsx`) and the App Privacy answers in
  `store/app-store/README.md`: photos taken are sent to the user's Hermes server.
- Handle simulators and devices with no camera, and a denied or restricted permission.
- Tests for the picker row, the permission flow and the size limit.
