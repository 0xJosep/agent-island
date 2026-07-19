#!/bin/bash
PORT="${AGENT_ISLAND_PORT:-4144}"
input=$(cat)
curl -s -m 1 -X POST "http://127.0.0.1:${PORT}/status" \
  -H 'Content-Type: application/json' \
  -d "$input" >/dev/null 2>&1 &
if command -v jq >/dev/null 2>&1; then
  echo "$input" | jq -r '"[\(.model.display_name // "Claude")] \(.workspace.current_dir // .cwd // "" | split("/") | last // "")"' 2>/dev/null
else
  echo "Claude"
fi
