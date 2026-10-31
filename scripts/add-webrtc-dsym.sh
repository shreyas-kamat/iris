#!/bin/sh
# WebRTC.framework ships prebuilt without debug symbols, so App Store Connect warns that the archive has no
# dSYM for its UUID. Generate an (empty) dSYM carrying that UUID and add it to the archive before uploading.
set -e
A="${1:-build/ios/archive/Runner.xcarchive}"
dsymutil "$A/Products/Applications/Runner.app/Frameworks/WebRTC.framework/WebRTC" -o "$A/dSYMs/WebRTC.framework.dSYM"
dwarfdump --uuid "$A/dSYMs/WebRTC.framework.dSYM"
