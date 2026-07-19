#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO/packaging/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$REPO/packaging/Info.plist")"
DMG="$REPO/dist/AgentIsland-v$VERSION.dmg"
SIGN="$REPO/.build/artifacts/sparkle/Sparkle/bin/sign_update"

[ -f "$DMG" ] || { echo "dmg not found: $DMG (run make-dmg.sh first)" >&2; exit 1; }

if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
  SIGNATURE="$("$SIGN" --ed-key-file "$SPARKLE_ED_KEY_FILE" "$DMG")"
else
  SIGNATURE="$("$SIGN" "$DMG")"
fi
PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
URL="https://github.com/0xJosep/agent-island/releases/download/v$VERSION/AgentIsland-v$VERSION.dmg"

cat > "$REPO/appcast.xml" <<EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Agent Island</title>
    <item>
      <title>Agent Island $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/0xJosep/agent-island/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$URL" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
EOF

echo "$REPO/appcast.xml"
