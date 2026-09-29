#!/usr/bin/env python3
"""Bounce runner.png around a herdr pane via the herdr graphics API."""
import base64, json, os, random, signal, socket, struct, sys, time

SOCK = os.environ.get("HERDR_SOCKET_PATH",
                      os.path.expanduser("~/.config/herdr/herdr.sock"))
SPRITES = os.path.expanduser("~/.claude/runner/sprites")
LAYER = "runner"
CELLS_W, CELLS_H = 6, 3   # on-screen size in terminal cells (before aspect fix)
FPS = 15
SPEEDUP = 1.18            # velocity multiplier on every wall hit
MAX_SPEED = 5.0           # ceiling, in cells per frame

pane = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("HERDR_PANE_ID", "")


def pick_sprite() -> str:
    """A random sprite per run, so you get a different one each turn.

    argv[2] names one directly, which is how you test a specific sprite.
    """
    if len(sys.argv) > 2:
        named = os.path.join(SPRITES, sys.argv[2] + ".png")
        if os.path.exists(named):
            return named
    choices = sorted(f for f in os.listdir(SPRITES) if f.endswith(".png"))
    if not choices:
        sys.exit(f"no sprites in {SPRITES}")
    return os.path.join(SPRITES, random.choice(choices))


SPRITE = pick_sprite()
# Record which one this run picked, so "why am I always seeing X" is answerable.
try:
    _slug = (pane or "none").replace(":", "_")
    with open(os.path.join(SPRITES, f"..last_{_slug}"), "w") as fh:
        fh.write(os.path.basename(SPRITE))
except OSError:
    pass
raw = open(SPRITE, "rb").read()
W, H = struct.unpack(">II", raw[16:24])
B64 = base64.b64encode(raw).decode()
# Keep the image's own proportions: the emoji sprites aren't all square, and
# stretching them to a fixed cell box makes them look squashed.
ASPECT = W / H

conn = None
def call(method, params):
    """One request per connection; herdr closes after replying."""
    global conn
    s = socket.socket(socket.AF_UNIX)
    s.connect(SOCK)
    s.sendall((json.dumps({"id": "bounce", "method": method,
                           "params": params}) + "\n").encode())
    s.settimeout(3)
    try:
        return s.recv(8192)
    finally:
        s.close()

def cells_w() -> int:
    """Width in cells that keeps the sprite's proportions.

    Terminal cells are about twice as tall as they are wide, so a square image
    needs roughly half as many columns as rows times two to come out square.
    """
    return max(2, round(CELLS_H * ASPECT * 2))


def draw(row, col):
    call("pane.graphics.set", {
        "pane_id": pane, "format": "png",
        "image_width": W, "image_height": H, "data_base64": B64,
        "placement": {"viewport_row": row, "viewport_col": col,
                      "grid_cols": cells_w(), "grid_rows": CELLS_H},
        "z_index": 10, "layer_id": LAYER})

def clear(*_):
    try:
        call("pane.graphics.clear", {"pane_id": pane, "layer_id": LAYER})
    except Exception:
        pass
    sys.exit(0)

def pane_size():
    """Real pane rect in cells, from herdr's layout (re-read as panes resize)."""
    try:
        r = json.loads(call("pane.layout", {"pane_id": pane}).decode())
        for entry in r["result"]["layout"]["panes"]:
            if entry["pane_id"] == pane:
                return entry["rect"]["width"], entry["rect"]["height"]
    except Exception:
        pass
    return 80, 24

def main():
    if not pane:
        sys.exit("no pane id")
    signal.signal(signal.SIGTERM, clear)
    signal.signal(signal.SIGINT, clear)
    cols, rows = pane_size()

    # Random start position and direction, so it doesn't always come from
    # the top-left corner. Position and velocity are floats; only the draw
    # call rounds to whole cells.
    x = float(random.randint(1, max(1, cols - CELLS_W)))
    y = float(random.randint(1, max(1, rows - CELLS_H)))
    vx = random.choice((-1.0, 1.0))
    vy = random.choice((-1.0, 1.0))
    tick = 0

    while True:
        max_x, max_y = max(1, cols - cells_w()), max(1, rows - CELLS_H)
        draw(int(round(y)), int(round(x)))
        time.sleep(1 / FPS)

        x += vx
        y += vy

        # Bounce off each wall, speeding up a little each time. Clamp the
        # position too, so a fast step can't tunnel past the edge.
        hit = False
        if x <= 0:
            x, vx, hit = 0.0, abs(vx), True
        elif x >= max_x:
            x, vx, hit = float(max_x), -abs(vx), True
        if y <= 0:
            y, vy, hit = 0.0, abs(vy), True
        elif y >= max_y:
            y, vy, hit = float(max_y), -abs(vy), True

        if hit:
            speed = (vx * vx + vy * vy) ** 0.5
            if speed < MAX_SPEED:
                vx *= SPEEDUP
                vy *= SPEEDUP

        tick += 1
        if tick % (FPS * 2) == 0:      # pick up window resizes
            cols, rows = pane_size()

if __name__ == "__main__":
    main()
