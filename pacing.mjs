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

// Whether the game should be paused, given the 1-minute load average and the core count.
// It pauses when there's more work waiting than cores (builds, many agents), and only
// resumes once the load is well below that, so it doesn't flicker on and off at the edge.
export function busyPause(load, cores, paused) {
  return paused ? load > cores * 0.7 : load > cores;
}

// The load limit: RUNNER_MAX_LOAD when it's a positive number, else the core count.
export const maxLoad = (value, cores) => (Number(value) > 0 ? Number(value) : cores);

// Frames to skip while paused so the next pass lands on a 2-second check frame.
export const framesToNextCheck = (frame, fps) => fps * 2 - (frame % (fps * 2));
