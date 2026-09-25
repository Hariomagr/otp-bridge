#!/bin/bash
# Generate the shared mascot icon for both apps:
#   - mac/AppIcon.icns              (macOS app bundle icon)
#   - android .../res/mipmap-*/     (Android launcher icons)
set -euo pipefail
cd "$(dirname "$0")"

ICONSET="build/AppIcon.iconset"
ANDROID_RES="../android/app/src/main/res"

rm -rf "$ICONSET"
mkdir -p build

echo "Rendering icon art…"
swiftc -swift-version 5 -target arm64-apple-macos14.0 tools/IconGen.swift -o build/icongen
./build/icongen "$ICONSET" "$ANDROID_RES"

echo "Packing AppIcon.icns…"
iconutil -c icns "$ICONSET" -o AppIcon.icns

echo "Done. mac/AppIcon.icns and android mipmap-* updated."
