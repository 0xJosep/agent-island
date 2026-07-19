#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO/packaging/Info.plist")"
DIST="$REPO/dist"
APP="$DIST/dmg-root/Agent Island.app"
DMG="$DIST/AgentIsland-v$VERSION.dmg"

swift build -c release --triple arm64-apple-macosx14.0 \
  --scratch-path "$REPO/.build-arm64" --package-path "$REPO"
BIN_ARM="$REPO/.build-arm64/arm64-apple-macosx/release/AgentIsland"

rm -rf "$DIST"
mkdir -p "$DIST"
BIN="$DIST/AgentIsland-universal"
if swift build -c release --triple x86_64-apple-macosx14.0 \
  --scratch-path "$REPO/.build-x86_64" --package-path "$REPO"; then
  lipo -create "$BIN_ARM" \
    "$REPO/.build-x86_64/x86_64-apple-macosx/release/AgentIsland" \
    -output "$BIN"
else
  echo "x86_64 build unavailable; shipping arm64-only" >&2
  cp "$BIN_ARM" "$BIN"
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/scripts"
cp "$REPO/packaging/Info.plist" "$APP/Contents/Info.plist"
mv "$BIN" "$APP/Contents/MacOS/AgentIsland"
cp "$REPO/scripts/agent-island-hook.sh" \
   "$REPO/scripts/agent-island-permission.sh" \
   "$REPO/scripts/agent-island-statusline.sh" \
   "$APP/Contents/Resources/scripts/"

codesign --force --deep -s - "$APP"

ln -s /Applications "$DIST/dmg-root/Applications"
cp "$REPO/README.md" "$DIST/dmg-root/README.md"

hdiutil create -volname "Agent Island" -srcfolder "$DIST/dmg-root" -ov -format UDZO "$DMG" >/dev/null

echo "$DMG"
