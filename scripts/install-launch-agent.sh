#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.youssef.agent-island"
PLIST_SRC="$REPO/launchd/$LABEL.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

swift build -c release --package-path "$REPO"

pkill -f "\.build/(debug|release)/AgentIsland" 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents"
cp "$PLIST_SRC" "$PLIST_DST"

launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST_DST"

echo "Installed. Agent Island now starts at login and stays running."
echo "Stop it with:   launchctl bootout gui/$UID_NUM/$LABEL"
echo "Logs:           ~/Library/Logs/AgentIsland.log"
