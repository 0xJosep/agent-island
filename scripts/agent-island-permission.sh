#!/bin/bash
PORT="${AGENT_ISLAND_PORT:-4144}"
PAYLOAD="$(cat)"
RESP=$(curl -s -m 590 --connect-timeout 1 -X POST "http://127.0.0.1:${PORT}/permission" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD" 2>/dev/null)
[ -n "$RESP" ] && printf '%s\n' "$RESP"
exit 0
