// How often and how big the game pane's frames are. Pure functions, so the
// tests can pin them down without Chrome or a terminal.

// Frames per second from DUNGEON_FPS: a whole number from 1 to 30, else 4.
// Frames go through the pane's terminal, which herdr parses like any output; at
// 8 full-size frames a second herdr stopped responding.
export function parseFps(value) {
  const n = Number(value);
  return Number.isInteger(n) && n >= 1 && n <= 30 ? n : 4;
}

// Screenshot scale that makes the image about the pane's own pixel width
// (8 px per column); more detail is wasted on a terminal cell. Never enlarges.
export const PX_PER_COL = 8;
export const shotScale = (paneCols, shotWidth) => Math.min(1, (paneCols * PX_PER_COL) / shotWidth);

// Whether to send this frame. An unchanged frame costs herdr nothing, so it is
// skipped, except after a move or resize (the pane was wiped) and every
// `refreshFrames` frames, in case something cleared the pane from outside.
export function shouldDraw({ moved, data, lastFrame, sinceDrawn, refreshFrames }) {
  return moved || data !== lastFrame || sinceDrawn >= refreshFrames;
}
