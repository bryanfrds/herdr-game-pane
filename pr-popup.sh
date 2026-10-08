#!/bin/bash
# Pop up a reaction when a pr-reviewer subagent finishes: GREEN FN for an approval
# (a picture and a video, taking turns), a crumbling Thanos memoji with FAHHH for requested changes.
# Claude Code SubagentStop hook: reads the hook JSON on stdin.
#   pr-popup.sh --show [green|fail]   just shows one (for testing)
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"     # the image and sounds sit next to this script
if [ "${1:-}" = "--show" ]; then
  RESULT="${2:-green}"
else
  INPUT=$(cat)
  # Only pr-reviewer, and only APPROVE or REQUEST_CHANGES. The final message is read from
  # the hook payload, or else the last assistant entry in the agent's transcript.
  # Same lookup as start.sh: a hook's PATH may not include where node lives.
  NODE=$(command -v node || { [ -x "$HOME/.local/bin/node" ] && echo "$HOME/.local/bin/node"; } || echo /opt/homebrew/bin/node)
  RESULT=$(printf '%s' "$INPUT" | "$NODE" -e '
let d; try { d = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch { d = {}; }
const kind = d.agent_type || d.subagent_type || "";
if (kind !== "pr-reviewer") { console.log("none"); process.exit(); }   // no type counts as not a review
let text = d.last_assistant_message || "";
const path = d.agent_transcript_path || "";
// The verdict can sit in plain text or inside the hand-back tool call, so look at the
// whole serialized entry, and use the last one that states a verdict.
if (!text.includes("VERDICT:") && path) {
  try {
    for (const line of require("fs").readFileSync(path, "utf8").split("\n")) {
      let e; try { e = JSON.parse(line); } catch { continue; }
      if (e.type !== "assistant") continue;
      const blob = JSON.stringify((e.message || {}).content || "");
      if (blob.includes("VERDICT:")) text = blob;
    }
  } catch {}
}
text = text.split("\\n").join("\n");
// The word must end the line, so a quoted template such as
// "VERDICT: APPROVE | REQUEST_CHANGES | COMMENT" does not read as an approval.
const m = [...text.matchAll(/VERDICT:[ \t]*([A-Z_]+)[ \t]*$/gm)];
const verdict = m.length ? m[m.length - 1][1] : "";
console.log({ APPROVE: "green", REQUEST_CHANGES: "fail" }[verdict] || "none");
' 2>/dev/null)
fi

# An approval alternates between the GREEN FN picture and the green-screen video (keyed
# out to see-through, with its own sound), one after the other. GREEN_FN=image or
# GREEN_FN=video picks one for good. Either is skipped if its file is missing.
next_green() {
  local img="$DIR/green-fn-cropped.png" vid="$DIR/green-fn-video.mov" turn="$DIR/.green_fn_next"
  case "${GREEN_FN:-cycle}" in
    image) [ -f "$img" ] && echo image; return ;;
    video) [ -f "$vid" ] && echo video; return ;;
  esac
  if [ -f "$img" ] && [ -f "$vid" ]; then
    local pick; pick=$(cat "$turn" 2>/dev/null); [ "$pick" = video ] || pick=image
    [ "$pick" = image ] && echo video > "$turn" || echo image > "$turn"
    echo "$pick"
  elif [ -f "$vid" ]; then echo video
  elif [ -f "$img" ]; then echo image
  fi
}

case "$RESULT" in
  # HOLD is how long it stays fully visible; fading in and out adds about 1s.
  green)
    case "$(next_green)" in
      image) IMG="$DIR/green-fn-cropped.png"; SOUND="green-fn"; HOLD=4.0 ;;   # border trimmed off
      video) IMG="$DIR/green-fn-video.mov";   SOUND="";         HOLD= ;;      # plays to its end, with its own sound
      *)     exit 0 ;;
    esac ;;
  fail)  IMG="$DIR/thanos.gif"; SOUND="fahhh"; HOLD=1.55 ;;  # ~2.5s in all, the GIF plays once; white made see-through
  *)     exit 0 ;;
esac
[ -f "$IMG" ] || exit 0

# The sound, if there is one: <name>.mp3/.m4a/.wav/.aiff next to this script.
if [ -n "$SOUND" ]; then
  for SND in "$DIR/$SOUND".{mp3,m4a,wav,aiff}; do
    [ -f "$SND" ] && { nohup afplay "$SND" >/dev/null 2>&1 & break; }
  done
fi

# A small card at the bottom centre of the screen that fades in, holds, and fades
# out. A picture gets rounded corners; a video keeps its own shape (its background is
# see-through) and holds until it finishes. Detached, so the hook returns straight away.
nohup osascript -l JavaScript - "$IMG" "$HOLD" "${GREEN_FN_VOLUME:-0.3}" >/dev/null 2>&1 <<'JXA' &
function run(argv) {
  ObjC.import('Cocoa');
  ObjC.import('QuartzCore');
  // JXA doesn't bridge AVFoundation's classes by name, so load it and look them up.
  $.NSBundle.bundleWithPath('/System/Library/Frameworks/AVFoundation.framework').load;
  const AV = (name) => $.NSClassFromString(name);
  const app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);
  const path = argv[0];
  const isVideo = /\.(mov|mp4|m4v)$/i.test(path);
  const area = $.NSScreen.mainScreen.visibleFrame;          // above the Dock
  let player = null, w = 240, h = 240;
  if (isVideo) {
    const item = AV('AVPlayerItem').playerItemWithURL($.NSURL.fileURLWithPath(path));
    player = AV('AVPlayer').playerWithPlayerItem(item);
    const vol = parseFloat(argv[2]);                 // the clip is mixed loud; GREEN_FN_VOLUME sets 0-1
    player.volume = Number.isFinite(vol) ? Math.min(1, Math.max(0, vol)) : 0.3;
    const track = item.asset.tracksWithMediaType('vide').firstObject;
    h = 320; w = 222;
    if (track) { const size = track.naturalSize; w = Math.round(h * size.width / size.height) || w; }
  }
  const rect = $.NSMakeRect(area.origin.x + (area.size.width - w) / 2, area.origin.y + 48, w, h);
  const win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
    rect, $.NSWindowStyleMaskBorderless, $.NSBackingStoreBuffered, false);
  win.level = $.NSStatusWindowLevel;
  win.opaque = false;
  win.backgroundColor = $.NSColor.clearColor;
  win.hasShadow = !isVideo;                                  // a shadow would outline the empty box
  win.ignoresMouseEvents = true;                             // never steals a click
  win.alphaValue = 0;
  let view;
  if (isVideo) {
    view = $.NSView.alloc.initWithFrame($.NSMakeRect(0, 0, w, h));
    view.wantsLayer = true;
    const layer = AV('AVPlayerLayer').playerLayerWithPlayer(player);
    layer.frame = $.NSMakeRect(0, 0, w, h);
    layer.videoGravity = 'AVLayerVideoGravityResizeAspect';
    view.layer.addSublayer(layer);
  } else {
    view = $.NSImageView.alloc.initWithFrame($.NSMakeRect(0, 0, w, h));
    view.image = $.NSImage.alloc.initWithContentsOfFile(path);
    view.imageScaling = $.NSImageScaleProportionallyUpOrDown;
    view.animates = true;                                    // GIFs play
    view.wantsLayer = true;
    view.layer.cornerRadius = 20;
    view.layer.masksToBounds = true;
  }
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
  if (player) player.play;
  fade(0, 1, 0.35);
  if (player) {
    // The player stops itself at the end; 30s caps a file that never plays.
    for (let t = 0; t < 30 && !(t > 0.5 && player.rate === 0); t += 0.1) wait(0.1);
  } else {
    wait(Number(argv[1]) || 2);
  }
  fade(1, 0, 0.6);
  win.orderOut(null);
}
JXA
exit 0
