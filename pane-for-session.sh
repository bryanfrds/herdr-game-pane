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
  NODE=$(command -v node || { [ -x "$HOME/.local/bin/node" ] && echo "$HOME/.local/bin/node"; } || echo /opt/homebrew/bin/node)
  PANE=$(herdr pane list 2>/dev/null | "$NODE" -e '
const py = (v) => v === null ? "" : v === true ? "True" : v === false ? "False" : typeof v === "object" ? JSON.stringify(v) : String(v);   // null: empty, so [ -n ] catches it
const obj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const sid = process.argv[1];
const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
const panes = obj(d) && obj(d.result) && "panes" in d.result ? d.result.panes : process.exit(1);
for (const p of panes) {
  if (!obj(p)) process.exit(1);
  // Empty or missing counts as no session, as the old python "or {}" did ([] is truthy in JS).
  const raw = p.agent_session;
  const s = !raw || (Array.isArray(raw) && raw.length === 0) ? {} : raw;
  if (!obj(s)) process.exit(1);           // the old .get() on a non-dict stopped here too
  if (s.value === sid) { if ("pane_id" in p) console.log(py(p.pane_id)); break; }
}
' -- "$SID" 2>/dev/null)
  [ -n "$PANE" ] && { echo "$PANE"; exit 0; }
fi
# Not found. A spare's inherited id is the unreliable case, so give up rather than
# open a game beside someone else's chat; a normal session's own id is fine.
[ "${CLAUDE_CODE_SESSION_KIND:-}" = "bg" ] && exit 0
echo "${HERDR_PANE_ID:-}"
