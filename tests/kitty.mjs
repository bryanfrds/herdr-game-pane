// Checks for kitty.mjs. Prints "ok <name>" or "FAIL <name>" per check; run by test_scripts.sh.
import { frame, eraseAll, IMAGES } from '../kitty.mjs';

const ESC = '\x1b';
const escapes = (s) => [...s.matchAll(/\x1b_G([^;]*);([^\x1b]*)\x1b\\/g)].map((m) => ({ keys: m[1], data: m[2] }));
const check = (name, holds) => console.log(`${holds ? 'ok' : 'FAIL'} ${name}`);

const png = 'A'.repeat(10000);
const place = { row: 2, col: 3, cols: 40, rows: 20 };
const a = frame(png, place, 0);
const b = frame(png, place, a.next);
const c = frame(png, place, b.next);
const chunks = escapes(a.out);

check('a 10000-character PNG goes in 3 chunks of at most 4096',
  chunks.length === 3 && chunks.every((x) => x.data.length <= 4096) && chunks.map((x) => x.data).join('') === png);
check('m=1 on every chunk but the last', chunks.map((x) => x.keys.match(/m=(\d)/)[1]).join('') === '110');
check('every chunk but the last is a multiple of 4 long', chunks.slice(0, -1).every((x) => x.data.length % 4 === 0));
const exact = escapes(frame('A'.repeat(8192), place, 0).out);
check('a PNG of exactly two chunks ends with m=0', exact.map((x) => x.keys.match(/m=(\d)/)[1]).join('') === '10');
check('the first chunk carries the image keys', chunks[0].keys === 'a=T,f=100,i=7,p=1,q=2,C=1,c=40,r=20,m=1');
check('later chunks stay quiet', chunks.slice(1).every((x) => x.keys.startsWith('q=2,')));
check('the cursor is hidden and parked at the frame first', a.out.startsWith(`${ESC}[?25l${ESC}[3;4H`));
check('ids alternate 7, 8, 7', [a.next, b.next, c.next].join() === '7,8,7');
check('the first frame deletes nothing', !a.out.includes('a=d'));
const del = `${ESC}_Ga=d,d=I,i=7,q=2;${ESC}\\`;
check('the old id is deleted only after the new frame is sent',
  b.out.endsWith(del) && b.out.indexOf(del) > b.out.lastIndexOf('i=8'));
check('erasing deletes both ids', eraseAll() === IMAGES.map((i) => `${ESC}_Ga=d,d=I,i=${i},q=2;${ESC}\\`).join(''));
check('erasing wipes the text only when asked', !eraseAll().includes(`${ESC}[2J`) && eraseAll(true).endsWith(`${ESC}[2J${ESC}[H`));
