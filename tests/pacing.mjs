// Checks for pacing.mjs. Prints "ok <name>" or "FAIL <name>" per check; run by test_scripts.sh.
import { parseFps, shotScale, shouldDraw, PX_PER_COL } from '../pacing.mjs';

const check = (name, holds) => console.log(`${holds ? 'ok' : 'FAIL'} ${name}`);

check('no DUNGEON_FPS means 4 a second', parseFps(undefined) === 4 && parseFps('') === 4);
check('a whole number from 1 to 30 is used', parseFps('1') === 1 && parseFps('12') === 12 && parseFps('30') === 30);
check('0, negatives, fractions, Infinity and junk fall back to 4',
  ['0', '-1', '2.5', 'Infinity', '31', 'fast'].every((v) => parseFps(v) === 4));
check('a wide shot is scaled to 8 px per pane column', shotScale(100, 1600) === (100 * PX_PER_COL) / 1600);
check('a shot narrower than the pane is never enlarged', shotScale(100, 400) === 1);

const base = { moved: false, data: 'A', lastFrame: 'A', sinceDrawn: 0, refreshFrames: 12 };
check('an unchanged frame in place is skipped', !shouldDraw(base));
check('a changed frame is drawn', shouldDraw({ ...base, data: 'B' }));
check('a moved or resized frame is drawn even if unchanged', shouldDraw({ ...base, moved: true }));
check('an unchanged frame is redrawn once the refresh comes round', shouldDraw({ ...base, sinceDrawn: 12 }));
