#!/bin/bash
PORT="${AGENT_ISLAND_PORT:-4144}"
if [ $# -gt 0 ]; then
  PAYLOAD="$1"
else
  PAYLOAD="$(cat)"
fi
if command -v jq >/dev/null 2>&1; then
  MERGED=$(jq -c --arg tb "${__CFBundleIdentifier:-}" --arg tp "${TERM_PROGRAM:-}" \
    '. + {term_bundle_id: $tb, term_program: $tp}' <<<"$PAYLOAD" 2>/dev/null)
  [ -n "$MERGED" ] && PAYLOAD="$MERGED"
fi
curl -s -m 1 -X POST "http://127.0.0.1:${PORT}/event" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD" >/dev/null 2>&1 &
exit 0
