#!/bin/bash
# Tests for the hook scripts. They run against a fake `herdr` and `node` in a
# throwaway home folder, so no real pane is opened and no real save is touched.
#   bash tests/test_scripts.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
PASS=0; FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; [ -n "${2:-}" ] && echo "       $2"; }
check() {   # check "name" "actual" "expected"
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}
has() {     # has "name" "file" "pattern": the file has a line matching it
  if grep -qE -- "$3" "$2" 2>/dev/null; then ok "$1"; else fail "$1" "no line matching [$3] in $(basename "$2")"; fi
}
hasnt() {
  if grep -qE -- "$3" "$2" 2>/dev/null; then fail "$1" "unexpected line matching [$3]"; else ok "$1"; fi
}

# A fresh fake home for each test: the scripts copied into ~/.claude/runner,
# both games present, and fake herdr/node first on the PATH.
setup() {
  T=$(mktemp -d) || exit 1
  export HOME="$T/home" LOG="$T/calls.log"
  RUN="$HOME/.claude/runner"
  mkdir -p "$RUN" "$T/bin" "$HOME/pokemon-wannabe" "$HOME/pixel-dungeon-crawler"
  cp "$REPO"/*.sh "$RUN/"
  touch "$HOME/pokemon-wannabe/index.html" "$HOME/pixel-dungeon-crawler/index.html" "$LOG"

  # herdr: logs every call; `pane list` prints $FAKE_PANES, `pane split` makes pane "new-1".
  cat > "$T/bin/herdr" <<'SH'
#!/bin/bash
echo "herdr $*" >> "$LOG"
case "$1 $2" in
  "pane list")  NONE='{"result":{"panes":[]}}'; echo "${FAKE_PANES:-$NONE}" ;;
  "pane split") [ -n "${SPLIT_FAILS:-}" ] && exit 1
                echo '{"result":{"pane":{"pane_id":"new-1"}}}' ;;
esac
SH
  # node: logs which game it was asked to draw, and where its save goes.
  cat > "$T/bin/node" <<'SH'
#!/bin/bash
echo "node $* game=${DUNGEON_GAME:-} profile=${DUNGEON_PROFILE:-} save=${DUNGEON_SAVE:-}" >> "$LOG"
SH
  # pkill: logged, never run, so a test can't stop a real game.
  printf '#!/bin/bash\necho "pkill $*" >> "$LOG"\n' > "$T/bin/pkill"
  chmod +x "$T/bin/herdr" "$T/bin/node" "$T/bin/pkill"
  export PATH="$T/bin:$ORIG_PATH"
  # Keep dungeon mode on machines without Chrome, such as CI.
  export DUNGEON_CHROME=fake HERDR_PANE_ID=env-pane
  unset RUNNER_MODE RUNNER_GAME CLAUDE_CODE_SESSION_KIND FAKE_PANES SPLIT_FAILS
  # stop.sh talks to herdr's socket directly; point it somewhere with nothing listening.
  export HERDR_SOCKET_PATH="$T/herdr.sock"
  unset HERDR_ENV HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_BIN_PATH
}
teardown() { rm -rf "$T"; }
trap 'rm -rf "${T:-}"' EXIT                     # even if the run is interrupted
# start.sh puts node in the background, so its line lands a moment later.
# settle [n]: wait until n games have started (default 1).
settle() {
  for _ in $(seq 50); do [ "$(grep -c '^node' "$LOG")" -ge "${1:-1}" ] && return; sleep 0.1; done
}
panes() {   # panes <pane id> <session id>: what `herdr pane list` reports
  export FAKE_PANES="{\"result\":{\"panes\":[{\"pane_id\":\"other\",\"agent_session\":{\"value\":\"someone-else\"}},{\"pane_id\":\"$1\",\"agent_session\":{\"value\":\"$2\"}}]}}"
}
hook() { echo "{\"session_id\":\"$1\"}"; }
ORIG_PATH=$PATH

echo "pane-for-session.sh"

setup; panes real-pane sess-1
check "finds the pane herdr says is showing the session" "$("$RUN/pane-for-session.sh" sess-1)" "real-pane"
teardown

setup; panes real-pane sess-1
check "falls back to the pane id it was started with" "$("$RUN/pane-for-session.sh" unknown)" "env-pane"
teardown

setup; panes real-pane sess-1; export CLAUDE_CODE_SESSION_KIND=bg
check "a background session herdr doesn't know gets no pane" "$("$RUN/pane-for-session.sh" unknown)" ""
teardown

setup
cat > "$T/bin/herdr" <<'SH'
#!/bin/bash
echo "not json"
SH
check "survives herdr printing something unexpected" "$("$RUN/pane-for-session.sh" sess-1)" "env-pane"
teardown

echo "start.sh"

setup; panes real-pane sess-1
hook sess-1 | "$RUN/start.sh"; settle
has   "splits the session's real pane, not the inherited one" "$LOG" "^herdr pane split real-pane --direction right"
hasnt "never splits the inherited pane" "$LOG" "pane split env-pane"
check "remembers the pane it opened" "$(cat "$RUN/.pane_real_pane_" 2>/dev/null)" "new-1"
has   "starts a game in the new pane" "$LOG" "^node .*dungeon.mjs new-1"
teardown

setup; panes p sess-1
for i in 1 2 3 4; do
  hook sess-1 | "$RUN/start.sh"; settle $i
  rm -f "$RUN"/.pid_*                           # as stop.sh would, between turns
done
check "takes turns between the two games" \
  "$(grep -o 'profile=[a-z]*' "$LOG" | tr '\n' ' ')" "profile=codemon profile= profile=codemon profile= "
teardown

setup; panes p sess-1; export RUNNER_GAME=dungeon
hook sess-1 | "$RUN/start.sh"; settle; rm -f "$RUN"/.pid_*
hook sess-1 | "$RUN/start.sh"; settle 2
hasnt "RUNNER_GAME pins one game" "$LOG" "profile=codemon"
teardown

setup; panes p sess-1; rm "$HOME/pokemon-wannabe/index.html"
hook sess-1 | "$RUN/start.sh"; settle          # CodeMon's turn, but it isn't there
has   "skips a game whose files are missing" "$LOG" "^node .*profile= "
teardown

setup; panes p sess-1; echo codemon > "$HOME/.claude/runner/.last_game_p_"
hook sess-1 | "$RUN/start.sh"; settle
has   "keeps a save per chat for the dungeon" "$LOG" "save=$HOME/.claude/runner/saves/sess-1.json"
teardown

setup; panes p sess-1
echo $$ > "$RUN/.pid_p_"                        # a game already running in this pane
hook sess-1 | "$RUN/start.sh"
hasnt "leaves a game that is still running alone" "$LOG" "pane split"
teardown

setup; panes p sess-1; echo stale-pane > "$RUN/.pane_p_"
hook sess-1 | "$RUN/start.sh"; settle
has   "closes a pane left behind by a run that died" "$LOG" "^herdr pane close stale-pane"
teardown

setup; unset HERDR_PANE_ID
hook sess-1 | "$RUN/start.sh"
check "does nothing outside herdr" "$(cat "$LOG")" ""
teardown

setup; panes p sess-1; export SPLIT_FAILS=1
hook sess-1 | "$RUN/start.sh"; sleep 0.3
hasnt "starts no game if the pane couldn't open" "$LOG" "^node"
check "and records no pane" "$(ls -A "$RUN" | grep -c '^\.pane_')" "0"
teardown

echo "stop.sh"

setup; panes p sess-1; echo game-pane > "$RUN/.pane_p_"
sleep 30 & GAME=$!; disown; echo $GAME > "$RUN/.pid_p_"
hook sess-1 | "$RUN/stop.sh"
has   "closes the pane start.sh opened" "$LOG" "^herdr pane close game-pane"
if kill -0 $GAME 2>/dev/null; then fail "stops the game"; kill $GAME; else ok "stops the game"; fi
check "forgets the pane and the game" "$(ls -A "$RUN" | grep -cE '^\.(pane|pid)_')" "0"
teardown

setup; panes p sess-1; echo mine > "$RUN/.pane_p_"; echo theirs > "$RUN/.pane_other_"
hook sess-1 | "$RUN/stop.sh"
hasnt "leaves other chats' games open" "$LOG" "pane close theirs"
teardown

echo "play.sh"

setup
"$RUN/play.sh" chess >/dev/null 2>&1; check "rejects a game it doesn't know" "$?" "64"
teardown

setup; echo game-pane > "$RUN/.play_pane"
"$RUN/play.sh" stop >/dev/null
has   "stop closes the pane it opened" "$LOG" "^herdr pane close game-pane"
has   "and stops only the game drawing into that pane" "$LOG" "^pkill -f dungeon.mjs game-pane\\$"
check "and forgets it" "$([ -f "$RUN/.play_pane" ] && echo still there)" ""
teardown

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
