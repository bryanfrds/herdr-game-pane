// Checks for pacing.mjs. Prints "ok <name>" or "FAIL <name>" per check; run by test_scripts.sh.
import { parseFps, shotScale, shouldDraw, busyPause, maxLoad, framesToNextCheck, PX_PER_COL } from '../pacing.mjs';

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

check('a calm Mac keeps playing', busyPause(4, 10, false) === false);
check('more work than cores pauses the game', busyPause(12, 10, false) === true);
check('a paused game waits until the load is well down', busyPause(9, 10, true) === true);
check('and then resumes', busyPause(6, 10, true) === false);
check('exactly at the core count is not yet busy', busyPause(10, 10, false) === false);
check('at exactly 70% a paused game resumes', busyPause(7, 10, true) === false);
check('RUNNER_MAX_LOAD is used when positive', maxLoad('20', 10) === 20);
check('0, junk or nothing falls back to the cores', ['0', '-3', 'fast', undefined].every((v) => maxLoad(v, 10) === 10));
check('a pause lands the next pass on a check frame', [0, 3, 7, 8, 13].every((f) => (f + framesToNextCheck(f, 4)) % 8 === 0));
