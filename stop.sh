#!/bin/bash
# Stop the runner for THIS pane only. Claude Code Stop hook.
set -u
DIR="$HOME/.claude/runner"
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
# Same lookup as start.sh, so the pane it opened is the one closed here.
NODE=$(command -v node || { [ -x "$HOME/.local/bin/node" ] && echo "$HOME/.local/bin/node"; } || echo /opt/homebrew/bin/node)
SESSION_ID=$("$NODE" -e '
const py = (v) => v === null ? "None" : v === true ? "True" : v === false ? "False" : typeof v === "object" ? JSON.stringify(v) : String(v);
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

# Clear the image layer from whichever pane it was drawn on.
for P in "$HERDR_PANE_ID" "$(cat "$PANEF" 2>/dev/null)"; do
  [ -n "$P" ] || continue
  # Ask herdr's socket to clear each layer. Any failure (no socket, no reply in 2s)
  # ends the whole clear, as before.
  "$NODE" -e '
const net = require("net"), path = require("path"), os = require("os");
const sock = process.env.HERDR_SOCKET_PATH || path.join(os.homedir(), ".config/herdr/herdr.sock");
const pane = process.argv[1];
const clear = (layer) => new Promise((done) => {
  const s = net.createConnection(sock);
  const quit = () => { s.destroy(); process.exit(0); };
  const timer = setTimeout(quit, 2000);
  s.on("error", quit);
  s.on("connect", () => s.write(JSON.stringify({ id: "stop", method: "pane.graphics.clear",
    params: { pane_id: pane, layer_id: layer } }) + "\n"));
  s.on("data", () => { clearTimeout(timer); s.destroy(); done(); });
});
(async () => { for (const layer of ["runner", "dungeon"]) await clear(layer); })();
' "$P" >/dev/null 2>&1
done

if [ -f "$PANEF" ]; then
  herdr pane close "$(cat "$PANEF")" >/dev/null 2>&1
  rm -f "$PANEF"
fi
exit 0
