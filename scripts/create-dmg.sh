#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Resources/Info.plist")"
VOLUME_NAME="RazerMon $VERSION"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build/release-$VERSION-arm64}"
DIST_ROOT="${DIST_ROOT:-$PROJECT_ROOT/dist}"
APP_PATH="$BUILD_ROOT/Build/Products/Release/RazerMon.app"
DMG_PATH="$DIST_ROOT/RazerMon-$VERSION-arm64.dmg"
STAGING_DIR="$(mktemp -d /tmp/razermon-dmg-staging.XXXXXX)"
WORK_DIR="$(mktemp -d /tmp/razermon-dmg-work.XXXXXX)"
RW_DMG="$WORK_DIR/RazerMon-$VERSION-rw.dmg"
MOUNTED_VOLUME=""

cleanup() {
    if [[ -n "$MOUNTED_VOLUME" && -d "$MOUNTED_VOLUME" ]]; then
        hdiutil detach "$MOUNTED_VOLUME" -quiet || true
    fi
    rm -rf "$STAGING_DIR" "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_ROOT"
rm -f "$DMG_PATH"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    xcodebuild \
    -project "$PROJECT_ROOT/RazerMon.xcodeproj" \
    -scheme RazerMon \
    -configuration Release \
    -derivedDataPath "$BUILD_ROOT" \
    -destination 'generic/platform=macOS' \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    build

codesign --force --deep --sign - "$APP_PATH"
ditto "$APP_PATH" "$STAGING_DIR/RazerMon.app"
ln -s /Applications "$STAGING_DIR/Applications"
mkdir -p "$STAGING_DIR/.background"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    xcrun swift \
    "$PROJECT_ROOT/scripts/make-dmg-background.swift" \
    "$STAGING_DIR/.background/background.png"
SetFile -a V "$STAGING_DIR/.background"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDRW \
    -ov "$RW_DMG"

MOUNTED_VOLUME="/Volumes/$VOLUME_NAME"
hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -mountpoint "$MOUNTED_VOLUME"
osascript "$PROJECT_ROOT/scripts/configure-dmg.applescript" "$VOLUME_NAME"
sync
hdiutil detach "$MOUNTED_VOLUME"
MOUNTED_VOLUME=""

hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$DMG_PATH"

shasum -a 256 "$DMG_PATH"
