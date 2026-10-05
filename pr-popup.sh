#!/bin/bash
# Pop up a reaction when a pr-reviewer subagent finishes: GREEN FN for an
# approval, a crumbling Thanos memoji with FAHHH for requested changes.
# Claude Code SubagentStop hook: reads the hook JSON on stdin.
#   pr-popup.sh --show [green|fail]   just shows one (for testing)
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"     # the image and sounds sit next to this script
if [ "${1:-}" = "--show" ]; then
  RESULT="${2:-green}"
else
  INPUT=$(cat)
  # Only pr-reviewer, and only an APPROVE verdict. The final message is read from
  # the hook payload, or else the last assistant entry in the agent's transcript.
  RESULT=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
kind = d.get("agent_type") or d.get("subagent_type") or ""
if kind != "pr-reviewer":                 # no type at all counts as not a review
    print("none"); sys.exit()
import re
text = d.get("last_assistant_message") or ""
path = d.get("agent_transcript_path") or ""
# The verdict can sit in plain text or inside the hand-back tool call, so look
# at the whole serialized entry, and use the last one that states a verdict.
if "VERDICT:" not in text and path:
    try:
        for line in open(path):
            e = json.loads(line)
            if e.get("type") == "assistant":
                blob = json.dumps(e.get("message", {}).get("content", ""))
                if "VERDICT:" in blob:
                    text = blob
    except (OSError, ValueError):
        pass
text = text.replace("\\n", "\n")
m = re.findall(r"VERDICT:\s*([A-Z_]+)", text)
verdict = m[-1] if m else ""
print({"APPROVE": "green", "REQUEST_CHANGES": "fail"}.get(verdict, "none"))
' 2>/dev/null)
fi

case "$RESULT" in
  # HOLD is how long it stays fully visible; fading in and out adds about 1s.
  green) IMG="$DIR/green-fn-cropped.png"; SOUND="green-fn"; HOLD=4.0 ;;   # border trimmed off
  fail)  IMG="$DIR/thanos.gif";            SOUND="fahhh";    HOLD=1.55 ;;  # ~2.5s in all, the GIF plays once; white made see-through
  *)     exit 0 ;;
esac
[ -f "$IMG" ] || exit 0

# The sound, if there is one: <name>.mp3/.m4a/.wav/.aiff next to this script.
for SND in "$DIR/$SOUND".{mp3,m4a,wav,aiff}; do
  [ -f "$SND" ] && { nohup afplay "$SND" >/dev/null 2>&1 & break; }
done

# A small rounded card at the bottom centre of the screen that fades in, holds,
# and fades out. Detached, so the hook returns straight away.
nohup osascript -l JavaScript - "$IMG" "$HOLD" >/dev/null 2>&1 <<'JXA' &
function run(argv) {
  ObjC.import('Cocoa');
  ObjC.import('QuartzCore');
  const app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);
  const img = $.NSImage.alloc.initWithContentsOfFile(argv[0]);
  const side = 240;
  const area = $.NSScreen.mainScreen.visibleFrame;          // above the Dock
  const rect = $.NSMakeRect(area.origin.x + (area.size.width - side) / 2,
                            area.origin.y + 48, side, side);
  const win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
    rect, $.NSWindowStyleMaskBorderless, $.NSBackingStoreBuffered, false);
  win.level = $.NSStatusWindowLevel;
  win.opaque = false;
  win.backgroundColor = $.NSColor.clearColor;
  win.hasShadow = true;
  win.ignoresMouseEvents = true;                             // never steals a click
  win.alphaValue = 0;
  const view = $.NSImageView.alloc.initWithFrame($.NSMakeRect(0, 0, side, side));
  view.image = img;
  view.imageScaling = $.NSImageScaleProportionallyUpOrDown;
  view.animates = true;                                      // GIFs play
  view.wantsLayer = true;
  view.layer.cornerRadius = 20;
  view.layer.masksToBounds = true;
  win.contentView = view;
  win.orderFrontRegardless;
  const loop = $.NSRunLoop.currentRunLoop;
  const wait = (s) => loop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(s));
  const fade = (from, to, secs) => {
    const steps = Math.round(secs * 60);
    for (let i = 1; i <= steps; i++) {
      const t = i / steps, ease = t * t * (3 - 2 * t);       // smoothstep
      win.alphaValue = from + (to - from) * ease;
      wait(1 / 60);
    }
  };
  fade(0, 1, 0.35);
  wait(Number(argv[1]) || 2);
  fade(1, 0, 0.6);
  win.orderOut(null);
}
JXA
exit 0
