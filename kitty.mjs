// Kitty graphics escape sequences for the game pane. Pure functions, so the
// tests can check the exact bytes without a terminal.

// Two image ids taken in turn: each frame lands before the one it replaces is
// deleted, so the pane never shows a gap between frames.
export const IMAGES = [7, 8];
const CHUNK = 4096;   // the protocol's limit on base64 characters per escape

export const kitty = (keys, payload = '') => `\x1b_G${keys};${payload}\x1b\\`;

// One frame: hide the cursor, park it where the frame goes, send the PNG in
// chunks under the id not on screen, then delete the id that was. C=1 keeps the
// cursor still, so the shell below never scrolls the picture; q=2 on every
// chunk keeps the terminal from typing replies into the pane's shell.
export function frame(png, { row, col, cols, rows }, shown) {
  const next = shown === IMAGES[0] ? IMAGES[1] : IMAGES[0];
  let out = `\x1b[?25l\x1b[${row + 1};${col + 1}H`;
  for (let i = 0; i < png.length; i += CHUNK) {
    const more = i + CHUNK < png.length ? 1 : 0;
    const keys = i === 0 ? `a=T,f=100,i=${next},p=1,q=2,C=1,c=${cols},r=${rows},m=${more}` : `q=2,m=${more}`;
    out += kitty(keys, png.slice(i, i + CHUNK));
  }
  if (shown) out += kitty(`a=d,d=I,i=${shown},q=2`);
  return { out, next };
}

// Delete both images, and with `clearScreen` also wipe the text under them.
export const eraseAll = (clearScreen = false) =>
  IMAGES.map((i) => kitty(`a=d,d=I,i=${i},q=2`)).join('') + (clearScreen ? '\x1b[2J\x1b[H' : '');
