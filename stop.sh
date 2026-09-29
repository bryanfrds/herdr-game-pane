#!/bin/bash
# Stop the runner for THIS pane only. Claude Code Stop hook.
set -u
DIR="$HOME/.claude/runner"
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
SLUG=$(echo "$HERDR_PANE_ID" | tr -c 'a-zA-Z0-9' '_')
PIDF="$DIR/.pid_$SLUG"
PANEF="$DIR/.pane_$SLUG"

if [ -f "$PIDF" ]; then
  kill "$(cat "$PIDF")" 2>/dev/null
  rm -f "$PIDF"
fi
sleep 0.2

# Clear the image layer from whichever pane it was drawn on.
for P in "$HERDR_PANE_ID" "$(cat "$PANEF" 2>/dev/null)"; do
  [ -n "$P" ] || continue
  python3 - "$P" <<'PY' >/dev/null 2>&1
import json, os, socket, sys
for layer in ("runner", "dungeon"):
    s = socket.socket(socket.AF_UNIX)
    s.connect(os.environ.get("HERDR_SOCKET_PATH",
              os.path.expanduser("~/.config/herdr/herdr.sock")))
    s.sendall((json.dumps({"id": "stop", "method": "pane.graphics.clear",
        "params": {"pane_id": sys.argv[1], "layer_id": layer}}) + "\n").encode())
    s.settimeout(2); s.recv(4096); s.close()
PY
done

if [ -f "$PANEF" ]; then
  herdr pane close "$(cat "$PANEF")" >/dev/null 2>&1
  rm -f "$PANEF"
fi
exit 0
