# Agent Island

A Dynamic Island for your MacBook notch that tracks AI agent sessions (Claude Code, Codex, or anything else). When an agent finishes a task or needs your input, the island springs open around the notch with the session's status; hover over it any time to see all active agents.

## How it works

The app draws a borderless always-on-top panel around the notch and runs a tiny HTTP server on `127.0.0.1:4144`. Agents report events by POSTing JSON to `/event`:

- Claude Code hooks (`SessionStart`, `UserPromptSubmit`, `Stop`, `Notification`, `SessionEnd`) are forwarded verbatim by `scripts/agent-island-hook.sh`.
- Codex's `notify` payload (`agent-turn-complete`) is understood natively — point `notify` at the same script.
- Any other agent can use the generic schema:

```json
{"source": "my-agent", "id": "unique-session-id", "type": "finished", "message": "Built the thing", "cwd": "/path/to/project"}
```

`type` is one of `started`, `working`, `finished`, `needs_input`, `idle`, `ended`.

Statuses: red = needs your input (stays open until handled), orange = working, green = finished (auto-collapses after a few seconds), gray = idle.

## Features

- **Interactive permission approval** — when Claude Code asks permission to run a tool, the island pops an Allow / Deny / Use terminal card. The `PermissionRequest` hook (`scripts/agent-island-permission.sh`) blocks on `POST /permission` until you click; Allow/Deny answer the prompt directly via `hookSpecificOutput.decision.behavior`, "Use terminal" (or the app being closed) falls back to the normal terminal prompt.
- **Live tool activity** — `PreToolUse`/`PostToolUse` hooks show what each session is doing right now ("Bash — Run test suite").
- **Subagent tracking** — `SubagentStart`/`SubagentStop` hooks show a per-session subagent count badge.
- **Usage + context display** — the Claude Code status line (`scripts/agent-island-statusline.sh`) forwards `rate_limits` and context-window usage to `POST /status`; the island shows usage bars in the footer and per-session context %.
- **Click to focus** — the hook script tags events with the terminal's bundle id (`__CFBundleIdentifier`); clicking a working session activates that terminal app. Clicking a finished session dismisses it.

## Build & run

```sh
swift build -c release
.build/release/AgentIsland
```

A sparkles menu bar item lets you send a test event or quit.

## Claude Code setup

Add hooks to `~/.claude/settings.json` (each event forwards its payload to the island):

```json
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "/Users/youssef/personal/agent-island/scripts/agent-island-hook.sh"}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/Users/youssef/personal/agent-island/scripts/agent-island-hook.sh"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "/Users/youssef/personal/agent-island/scripts/agent-island-hook.sh"}]}],
    "Notification": [{"hooks": [{"type": "command", "command": "/Users/youssef/personal/agent-island/scripts/agent-island-hook.sh"}]}],
    "SessionEnd": [{"hooks": [{"type": "command", "command": "/Users/youssef/personal/agent-island/scripts/agent-island-hook.sh"}]}]
  }
}
```

The script fires curl in the background with a 1s timeout and always exits 0, so hooks add no latency and nothing breaks when the app isn't running.

## Codex setup

In `~/.codex/config.toml`:

```toml
notify = ["/Users/youssef/personal/agent-island/scripts/agent-island-hook.sh"]
```

## Start at login

```sh
swift build -c release
cp launchd/com.youssef.agent-island.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.youssef.agent-island.plist
```
