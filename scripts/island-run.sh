#!/bin/bash
PORT="${AGENT_ISLAND_PORT:-4144}"

NAME=""
if [ "$1" = "--name" ]; then
  if [ -z "$2" ]; then
    echo "usage: island-run.sh [--name <label>] <command> [args...]" >&2
    exit 64
  fi
  NAME="$2"
  shift 2
fi
if [ $# -eq 0 ]; then
  echo "usage: island-run.sh [--name <label>] <command> [args...]" >&2
  exit 64
fi

CMD_STR="$*"
LABEL="${NAME:-$CMD_STR}"
ID="run-$$-$RANDOM"

esc() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\t'/ }"
  printf '%s' "$s"
}

trunc() {
  local s="$1"
  if [ "${#s}" -gt 80 ]; then
    printf '%s…' "${s:0:79}"
  else
    printf '%s' "$s"
  fi
}

post() {
  curl -s -m 1 -X POST "http://127.0.0.1:${PORT}/event" \
    -H 'Content-Type: application/json' \
    -d "{\"source\":\"shell\",\"id\":\"${ID}\",\"type\":\"$1\",\"message\":\"$(esc "$2")\",\"cwd\":\"$(esc "$PWD")\",\"term_bundle_id\":\"$(esc "${__CFBundleIdentifier:-}")\"}" \
    >/dev/null 2>&1
  return 0
}

START=$(date +%s)
post working "$(trunc "$CMD_STR")"

INTERRUPTED=0
trap 'INTERRUPTED=1' INT
"$@"
STATUS=$?
trap - INT

DUR=$(( $(date +%s) - START ))
SHORT_LABEL="$(trunc "$LABEL")"

if [ "$INTERRUPTED" -eq 1 ]; then
  post needs_input "${SHORT_LABEL} — interrupted after ${DUR}s"
  exit 130
fi

if [ "$STATUS" -eq 0 ]; then
  post finished "${SHORT_LABEL} — done in ${DUR}s"
else
  post needs_input "${SHORT_LABEL} — failed (exit ${STATUS}) after ${DUR}s"
fi
exit "$STATUS"
