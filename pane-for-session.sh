#!/bin/bash
# Print the herdr pane a Claude session really lives in.   Usage: pane-for-session.sh <session id>
#
# $HERDR_PANE_ID can't be trusted on its own. Claude Code keeps spare background
# processes warm and hands one to the next chat you open, and a spare keeps the
# environment of whichever pane it was started from. A chat in one pane then
# carries another pane's id, and its game opened beside the wrong chat.
# herdr knows which session each pane is showing, so ask it first.
set -u
SID="${1:-}"
if [ -n "$SID" ]; then
  PANE=$(herdr pane list 2>/dev/null | python3 -c '
import json, sys
sid = sys.argv[1]
for p in json.load(sys.stdin)["result"]["panes"]:
    if (p.get("agent_session") or {}).get("value") == sid:
        print(p["pane_id"]); break
' "$SID" 2>/dev/null)
  [ -n "$PANE" ] && { echo "$PANE"; exit 0; }
fi
# Not found. A spare's inherited id is the unreliable case, so give up rather than
# open a game beside someone else's chat; a normal session's own id is fine.
[ "${CLAUDE_CODE_SESSION_KIND:-}" = "bg" ] && exit 0
echo "${HERDR_PANE_ID:-}"
