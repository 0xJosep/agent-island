#!/bin/bash
PORT="${AGENT_ISLAND_PORT:-4144}"

NAME=""
TAIL=1
while [ $# -gt 0 ]; do
  case "$1" in
    --name)
      if [ -z "$2" ]; then
        echo "usage: island-run.sh [--name <label>] [--no-tail] <command> [args...]" >&2
        exit 64
      fi
      NAME="$2"
      shift 2
      ;;
    --no-tail)
      TAIL=0
      shift
      ;;
    *)
      break
      ;;
  esac
done
if [ $# -eq 0 ]; then
  echo "usage: island-run.sh [--name <label>] [--no-tail] <command> [args...]" >&2
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

trunc_line() {
  local s="$1"
  if [ "${#s}" -gt 60 ]; then
    printf '%s…' "${s:0:59}"
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
SHORT_CMD="$(trunc "$CMD_STR")"
post working "$SHORT_CMD"

INTERRUPTED=0
if [ "$TAIL" -eq 1 ]; then
  STATE="$(mktemp "${TMPDIR:-/tmp}/island-run.XXXXXX")"
  ANSI_ESC="$(printf '\033')"

  poster() {
    local raw clean
    while :; do
      sleep 2
      raw="$(cat -- "$STATE" 2>/dev/null)"
      clean="$(printf '%s' "$raw" \
        | sed -E "s/${ANSI_ESC}\[[0-9;?]*[[:alpha:]]//g" \
        | tr -d '\r' | tr -s '[:space:]' ' ')"
      clean="${clean# }"
      clean="${clean% }"
      if [ -n "$clean" ]; then
        post working "${SHORT_CMD} · $(trunc_line "$clean")"
      fi
    done
  }
  poster &
  POSTER_PID=$!
  trap 'kill "$POSTER_PID" 2>/dev/null; rm -f "$STATE"' EXIT

  trap 'INTERRUPTED=1' INT
  "$@" 2>&1 | while IFS= read -r line; do
    printf '%s\n' "$line"
    if [ -n "${line//[[:space:]]/}" ]; then
      printf '%s\n' "$line" > "$STATE"
    fi
  done
  STATUS="${PIPESTATUS[0]}"
  trap - INT

  kill "$POSTER_PID" 2>/dev/null
  wait "$POSTER_PID" 2>/dev/null
  rm -f "$STATE"
  trap - EXIT
else
  trap 'INTERRUPTED=1' INT
  "$@"
  STATUS=$?
  trap - INT
fi

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
