#!/bin/bash
# Build OTPBridge.app from the Swift sources with swiftc (no Xcode project
# needed). Ad-hoc signs so local notifications work. Run: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/OTP Bridge.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

echo "Compiling…"
swiftc \
    -swift-version 5 \
    -target arm64-apple-macos14.0 \
    -O \
    -o "$MACOS/OTPBridge" \
    Sources/*.swift

cp Info.plist "$APP/Contents/Info.plist"

# App icon (run ./gen-icons.sh to (re)generate AppIcon.icns).
if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$RES/AppIcon.icns"
fi

echo "Ad-hoc signing…"
codesign --force --deep --sign - "$APP"

echo "Built: $APP"
echo "Run it with: open \"$APP\"   (or double-click in Finder)"
