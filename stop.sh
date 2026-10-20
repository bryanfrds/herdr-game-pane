#!/bin/bash
# Stop the runner for THIS pane only. Claude Code Stop hook.
set -u
DIR="$HOME/.claude/runner"
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
# Same lookup as start.sh, so the pane it opened is the one closed here.
NODE=$(command -v node || { [ -x "$HOME/.local/bin/node" ] && echo "$HOME/.local/bin/node"; } || echo /opt/homebrew/bin/node)
SESSION_ID=$("$NODE" -e '
const py = (v) => v === null ? "" : v === true ? "True" : v === false ? "False" : typeof v === "object" ? JSON.stringify(v) : String(v);   // null: empty, so [ -n ] catches it
const obj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const d = JSON.parse(require("fs").readFileSync(0, "utf8"));   // bad JSON: throws, prints nothing
if (!obj(d)) process.exit(1);
console.log("session_id" in d ? py(d.session_id) : "");
' 2>/dev/null)
HERDR_PANE_ID=$("$DIR/pane-for-session.sh" "$SESSION_ID")
[ -n "$HERDR_PANE_ID" ] || exit 0
SLUG=$(echo "$HERDR_PANE_ID" | tr -c 'a-zA-Z0-9' '_')
PIDF="$DIR/.pid_$SLUG"
PANEF="$DIR/.pane_$SLUG"

if [ -f "$PIDF" ]; then
  kill "$(cat "$PIDF")" 2>/dev/null
  rm -f "$PIDF"
fi
sleep 0.2

if [ -f "$PANEF" ]; then
  herdr pane close "$(cat "$PANEF")" >/dev/null 2>&1
  rm -f "$PANEF"
fi
exit 0
