#!/bin/bash
# Builds PinMac.app and PinMac-<version>.dmg into ./build
# Usage: scripts/build.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
VERSION="${VERSION#v}"
BUILD=build
APP="$BUILD/PinMac.app"
DMG="$BUILD/PinMac-$VERSION.dmg"

echo "▸ Compiling (release, universal)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/PinMac"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PinMac"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

# Delete Resources/AppIcon.icns to regenerate it after changing the icon.
if [ ! -f Resources/AppIcon.icns ]; then
    echo "▸ Generating icon"
    ICONSET="$BUILD/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    swiftc -parse-as-library -O scripts/make-icon.swift Sources/PinMac/PinShape.swift -o "$BUILD/make-icon"
    "$BUILD/make-icon" "$BUILD/icon.png"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$BUILD/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$BUILD/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
    rm -rf "$ICONSET" "$BUILD/make-icon"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Set SIGN_IDENTITY (e.g. "Apple Development: you@example.com") to sign with a
# real certificate; macOS then keeps PinMac's permissions across rebuilds.
IDENTITY="${SIGN_IDENTITY:--}"
echo "▸ Signing (${SIGN_IDENTITY:-ad-hoc})"
codesign --force --deep --sign "$IDENTITY" "$APP"

echo "▸ Creating $DMG"
STAGING="$BUILD/dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "PinMac" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "✓ Done: $DMG"
