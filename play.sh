#!/bin/bash
# Play a game in a herdr side pane.   Usage: play.sh [codemon|dungeon]
# Closes itself with Ctrl-C, or `play.sh stop`.
set -u
DIR="$HOME/.claude/runner"
GAME="${1:-codemon}"
PANEF="$DIR/.play_pane"

if [ "$GAME" = "stop" ]; then
  # Stop only the renderer drawing into our pane. A blanket `pkill dungeon.mjs`
  # also killed the games every other Claude session had open.
  if [ -f "$PANEF" ]; then
    PANE=$(cat "$PANEF")
    pkill -f "dungeon.mjs $PANE\$" >/dev/null 2>&1
    herdr pane close "$PANE" >/dev/null 2>&1
  fi
  rm -f "$PANEF"
  echo "stopped"; exit 0
fi

case "$GAME" in
  codemon) HTML="$HOME/pokemon-wannabe/index.html";      PROFILE=codemon ;;
  dungeon) HTML="$HOME/pixel-dungeon-crawler/index.html"; PROFILE=dungeon ;;
  *) echo "usage: play.sh [codemon|dungeon|stop]" >&2; exit 64 ;;
esac
[ -f "$HTML" ] || { echo "no game at $HTML" >&2; exit 1; }
[ -n "${HERDR_PANE_ID:-}" ] || { echo "run this inside herdr" >&2; exit 1; }

NODE=$(command -v node || { [ -x "$HOME/.local/bin/node" ] && echo "$HOME/.local/bin/node"; } || echo /opt/homebrew/bin/node)
NEW=$(herdr pane split "$HERDR_PANE_ID" --direction right --ratio 0.6 2>/dev/null \
      | "$NODE" -e '
const py = (v) => v === null ? "None" : v === true ? "True" : v === false ? "False" : typeof v === "object" ? JSON.stringify(v) : String(v);
const obj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
const r = obj(d) && "result" in d ? d.result : process.exit(1);
const p = obj(r) && "pane" in r ? r.pane : process.exit(1);
console.log(obj(p) && "pane_id" in p ? py(p.pane_id) : process.exit(1));
' 2>/dev/null)
[ -n "$NEW" ] || { echo "could not open a pane" >&2; exit 1; }
echo "$NEW" > "$PANEF"
herdr pane rename "$NEW" "$GAME" >/dev/null 2>&1
herdr pane focus --pane "$NEW" --direction left >/dev/null 2>&1

echo "playing $GAME in pane $NEW  (Ctrl-C to stop)"
trap 'herdr pane close "$NEW" >/dev/null 2>&1; rm -f "$PANEF"; exit 0' INT TERM
# CodeMon keeps no localStorage save; the dungeon keeps one per pane.
if [ "$PROFILE" = codemon ]; then
  DUNGEON_GAME="$HTML" DUNGEON_PROFILE=codemon DUNGEON_SAVE_KEY="" \
    "$NODE" "$DIR/dungeon.mjs" "$NEW"
else
  mkdir -p "$DIR/saves"
  DUNGEON_GAME="$HTML" DUNGEON_PROFILE=dungeon DUNGEON_SAVE="$DIR/saves/play.json" \
    "$NODE" "$DIR/dungeon.mjs" "$NEW"
fi
