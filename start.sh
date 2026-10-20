#!/bin/bash
# Start a game for THIS pane. Claude Code UserPromptSubmit hook.
# Streams ~/pixel-dungeon-crawler or ~/pokemon-wannabe into a right-side pane.
set -u
# No browser to run the game in: no game.
[ ! -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ] \
  && ! ls "$HOME"/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-mac-arm64/chrome-headless-shell >/dev/null 2>&1 \
  && [ -z "${DUNGEON_CHROME:-}" ] && exit 0
DIR="$HOME/.claude/runner"
[ -n "${HERDR_PANE_ID:-}" ] || exit 0     # not inside herdr at all
# What to play: RUNNER_GAME, else the choice the menu bar picker saved (auto, dungeon,
# codemon or off): the file's first line without spaces or a Windows \r, the same rule as
# savedChoice in picker/Choice.swift. Anything else plays both in turn.
CHOICE="${RUNNER_GAME:-$(head -n 1 "$DIR/choice" 2>/dev/null | tr -d ' \t\r')}"
[ "$CHOICE" = off ] && exit 0

# The hook's JSON arrives once on stdin; keep it, both the pane lookup and the
# save key need the session id from it.
HOOK_INPUT=$(cat)
NODE=$(command -v node || { [ -x "$HOME/.local/bin/node" ] && echo "$HOME/.local/bin/node"; } || echo /opt/homebrew/bin/node)
SESSION_ID=$(printf '%s' "$HOOK_INPUT" | "$NODE" -e '
const py = (v) => v === null ? "" : v === true ? "True" : v === false ? "False" : typeof v === "object" ? JSON.stringify(v) : String(v);   // null: empty, so [ -n ] catches it
const obj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const d = JSON.parse(require("fs").readFileSync(0, "utf8"));   // bad JSON: throws, prints nothing
if (!obj(d)) process.exit(1);
console.log("session_id" in d ? py(d.session_id) : "");
' 2>/dev/null)
HERDR_PANE_ID=$("$DIR/pane-for-session.sh" "$SESSION_ID")
[ -n "$HERDR_PANE_ID" ] || exit 0

# Per-pane pid file, so parallel agents don't fight over one another.
SLUG=$(echo "$HERDR_PANE_ID" | tr -c 'a-zA-Z0-9' '_')
PIDF="$DIR/.pid_$SLUG"

# Already bouncing in this pane? Leave it alone.
if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
  exit 0
fi

# A busy Mac gets no game or runner: with more work waiting than cores (builds, many
# agents), they only add to the lag. RUNNER_MAX_LOAD overrides the core count when it's a
# plain positive decimal, the same rule as maxLoad in pacing.mjs, so the start check and the
# in-game pause agree. LC_ALL=C and the comma swap keep the load a plain decimal in any locale.
LOAD=$(LC_ALL=C sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' | tr , .)
MAX_LOAD="${RUNNER_MAX_LOAD:-}"
case "$MAX_LOAD" in *[!0-9.]*|*.*.*) MAX_LOAD= ;; esac
awk -v m="$MAX_LOAD" 'BEGIN { exit !(m + 0 > 0) }' || MAX_LOAD=$(sysctl -n hw.ncpu 2>/dev/null)
if [ -n "$LOAD" ] && [ -n "$MAX_LOAD" ] && awk -v l="$LOAD" -v m="$MAX_LOAD" 'BEGIN { exit !(l > m) }'; then
  exit 0
fi

# A side pane from a run that died without the Stop hook: close it, don't stack another.
if [ -f "$DIR/.pane_$SLUG" ]; then
  herdr pane close "$(cat "$DIR/.pane_$SLUG")" >/dev/null 2>&1
  rm -f "$DIR/.pane_$SLUG"
fi

NEW=$(herdr pane split "$HERDR_PANE_ID" --direction right --ratio 0.6 2>/dev/null \
      | "$NODE" -e '
const py = (v) => v === null ? "" : v === true ? "True" : v === false ? "False" : typeof v === "object" ? JSON.stringify(v) : String(v);   // null: empty, so [ -n ] catches it
const obj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
const r = obj(d) && "result" in d ? d.result : process.exit(1);
const p = obj(r) && "pane" in r ? r.pane : process.exit(1);
console.log(obj(p) && "pane_id" in p ? py(p.pane_id) : process.exit(1));
' 2>/dev/null)
[ -n "$NEW" ] || exit 0
echo "$NEW" > "$DIR/.pane_$SLUG"
herdr pane rename "$NEW" dungeon >/dev/null 2>&1
herdr pane focus --pane "$NEW" --direction left >/dev/null 2>&1
TARGET="$NEW"

# One save per chat, keyed by Claude's session id (from the hook's JSON on stdin),
# so a resumed chat picks its own hero back up. Falls back to the pane id.
SID=$(printf '%s' "$SESSION_ID" | tr -c 'a-zA-Z0-9-' '_' | sed 's/_*$//')
mkdir -p "$DIR/saves"

# Pick a game for this turn. A choice of dungeon or codemon pins it; otherwise the
# two alternate, so you get a different one each turn.
case "$CHOICE" in dungeon|codemon) GAME_PICK=$CHOICE ;; *) GAME_PICK= ;; esac
if [ -z "$GAME_PICK" ]; then
  # Strict alternation, not a coin flip: independent 50/50 draws cluster, and
  # three dungeons in a row reads as "codemon is broken" rather than as luck.
  # Per-pane, so parallel agents alternate independently instead of sharing
  # one cursor and interleaving into what looks random again.
  LAST=$(cat "$DIR/.last_game_$SLUG" 2>/dev/null)
  [ "$LAST" = "codemon" ] && GAME_PICK=dungeon || GAME_PICK=codemon
fi
# A game whose files are missing is skipped rather than showing a blank pane.
[ -f "$HOME/pokemon-wannabe/index.html" ] || GAME_PICK=dungeon
[ -f "$HOME/pixel-dungeon-crawler/index.html" ] || GAME_PICK=codemon

echo "$GAME_PICK" > "$DIR/.last_game_$SLUG"
echo "$(date +%H:%M:%S) $GAME_PICK ${CHOICE:-auto} $TARGET" >> "$DIR/picks.log"

if [ "$GAME_PICK" = "codemon" ]; then
  # CodeMon keeps no localStorage save, so no key and no save file.
  herdr pane rename "$TARGET" codemon >/dev/null 2>&1
  DUNGEON_GAME="$HOME/pokemon-wannabe/index.html" \
  DUNGEON_PROFILE=codemon \
  DUNGEON_SAVE_KEY="" \
    nohup "$NODE" "$DIR/dungeon.mjs" "$TARGET" >/dev/null 2>&1 &
else
  DUNGEON_SAVE="$DIR/saves/${SID:-$SLUG}.json" \
    nohup "$NODE" "$DIR/dungeon.mjs" "$TARGET" >/dev/null 2>&1 &
fi
echo $! > "$PIDF"
exit 0
