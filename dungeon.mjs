#!/usr/bin/env node
// Stream ~/pixel-dungeon-crawler into a herdr pane via the herdr graphics API.
// Headless Chrome runs the game (auto-play is on by default); we screenshot the
// play area a few times a second and push each frame as a PNG image layer.
// Chrome talks over --remote-debugging-pipe, so it dies with this process.
import { spawn, execSync } from 'node:child_process';
import { connect } from 'node:net';
import { mkdtempSync, rmSync, writeFileSync, readdirSync, readFileSync, renameSync, existsSync } from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import { join } from 'node:path';

const PANE = process.argv[2] || process.env.HERDR_PANE_ID;
const SOCK = process.env.HERDR_SOCKET_PATH || join(homedir(), '.config/herdr/herdr.sock');
const GAME = process.env.DUNGEON_GAME || join(homedir(), 'pixel-dungeon-crawler/index.html');
// Prefer Playwright's chrome-headless-shell (~300 MB here vs ~1.3 GB for full Chrome);
// fall back to the installed Chrome if it's not there.
function headlessShell() {
  const root = join(homedir(), 'Library/Caches/ms-playwright');
  try {
    const dirs = readdirSync(root).filter((d) => d.startsWith('chromium_headless_shell-')).sort().reverse();
    for (const d of dirs) {
      const bin = join(root, d, 'chrome-headless-shell-mac-arm64/chrome-headless-shell');
      if (existsSync(bin)) return bin;
    }
  } catch { /* no Playwright cache */ }
  return null;
}
const SHELL = process.env.DUNGEON_CHROME ? null : headlessShell();
const CHROME = process.env.DUNGEON_CHROME || SHELL ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
// Memory savers. --single-process only works in the headless shell, not full Chrome.
const LEAN_FLAGS = [
  '--disable-gpu', '--disable-background-networking', '--disable-component-update',
  '--disable-sync', '--disable-default-apps', '--renderer-process-limit=1',
  '--disable-site-isolation-trials', '--js-flags=--max-old-space-size=96',
  '--disable-features=Translate,OptimizationHints,MediaRouter,BackForwardCache,site-per-process,IsolateOrigins,AudioServiceOutOfProcess',
  ...(SHELL ? ['--single-process'] : []),
];
const LAYER = process.env.DUNGEON_LAYER || 'dungeon';
// Chrome's profile is thrown away each run, so the game's save lives here instead.
const SAVE_FILE = process.env.DUNGEON_SAVE || join(homedir(), '.claude/runner/dungeon-save.json');
// Which localStorage key holds the save. Empty means the game has no save at all
// (CodeMon doesn't), in which case restore and persist are skipped.
const SAVE_KEY = process.env.DUNGEON_SAVE_KEY ?? 'pixelDungeonSave';
// Per-game hooks. "dungeon" keeps exactly the behaviour this file shipped with.
// A profile says how to tell the game has loaded, what rectangle to capture, and
// what to do each frame to keep it playing itself.
const PROFILES = {
  dungeon: {
    ready: `!!document.querySelector('.viewport-overlay-top')`,
    clip: `(() => {
      const top = document.querySelector('.viewport-overlay-top').getBoundingClientRect();
      const cv = document.querySelector('.canvas-container').getBoundingClientRect();
      return { x: cv.left, y: top.top, width: cv.width, height: cv.bottom - top.top };
    })()`,
    // Auto-play doesn't respawn on its own; the caller presses RESPAWN after a beat.
    dead: `document.getElementById('overlayBtn').textContent === 'RESPAWN' &&
           !document.getElementById('gameOverlay').classList.contains('hidden')`,
    revive: `document.getElementById('overlayBtn').click()`,
    tick: null,
  },
  codemon: {
    ready: `!!document.getElementById('explorationCanvas')`,
    // The whole board: team and items on the left, the map in the middle, status
    // and battle log on the right. Cropping to just the map showed an empty grid
    // with one dot, which reads as broken rather than as a game.
    // No fixed cap on the crop: the viewport now follows the pane's shape, so a
    // tall pane gives a tall layout and a 900px ceiling would chop the map off.
    // Mid-fight, crop to the battle panel alone so it fills the pane; the team
    // list and nav buttons aren't worth the space then. Otherwise show the board.
    dynamicClip: true,
    clip: `(() => {
      const bv = document.getElementById('battleView');
      const fighting = bv && !bv.classList.contains('hidden') && bv.offsetParent !== null;
      const app = fighting ? bv : (document.querySelector('.app-container') || document.body);
      const r = app.getBoundingClientRect();
      return { x: Math.max(0, r.left), y: Math.max(0, r.top),
               width: Math.min(r.width, window.innerWidth),
               height: Math.min(r.height, window.innerHeight) };
    })()`,
    dead: null,
    revive: null,
    // CodeMon takes button clicks, not keys, and has no AI of its own: walk it
    // around so the pane shows something moving rather than a frozen sprite.
    // Walk about, pick fights, and fight them. Without the forced encounters the
    // hero just wanders an empty grid and nothing ever happens.
    tick: `(() => {
      // Wait for the current exchange to finish animating before acting again.
      const game = window.gameInstance;
      if (game && game.fxBusy && game.fxBusy()) return;
      // A new run opens on the starter picker; choose one so play can begin.
      const starterModal = document.getElementById('starterModal');
      if (starterModal && !starterModal.classList.contains('hidden')) {
        const cards = starterModal.querySelectorAll('.starter-card');
        if (cards.length) cards[Math.floor(Math.random() * cards.length)].click();
        return;
      }
      const click = (id) => {
        const el = document.getElementById(id);
        if (el && !el.disabled && el.offsetParent !== null) { el.click(); return true; }
        return false;
      };
      const battle = document.getElementById('battleView');
      const inBattle = battle && !battle.classList.contains('hidden')
                       && battle.offsetParent !== null;
      // Attacking is two steps: moveSelectBtn opens a modal, then a .move-btn
      // inside it actually attacks. Clicking only the first leaves it stuck open.
      const moveModal = document.getElementById('moveSelectModal');
      if (moveModal && !moveModal.classList.contains('hidden')
          && moveModal.offsetParent !== null) {
        const moves = moveModal.querySelectorAll('.move-btn');
        if (moves.length) { moves[Math.floor(Math.random() * moves.length)].click(); }
        else click('closeMoveModalBtn');
        return;
      }
      const catchModal = document.getElementById('catchModal');
      if (catchModal && !catchModal.classList.contains('hidden')
          && catchModal.offsetParent !== null) {
        if (!click('confirmCatchBtn')) click('cancelCatchBtn');
        return;
      }
      if (inBattle) {
        // Heal before it gets fatal. Without this the starter grinds down to 1 HP,
        // faints, and the run dies with three unused potions in the bag.
        // Parsed by hand, not with a regex: this whole function lives in a JS
        // template literal, where a regex's escaped slash collapses to a bare one
        // and ends the literal early - which threw on every single frame.
        const hpText = (document.getElementById('allyHpText') || {}).textContent || '';
        const digitsOf = (t) => {
          let out = '';
          for (let i = 0; i < t.length; i++) {
            const c = t.charCodeAt(i);
            if (c >= 48 && c <= 57) out += t[i];
          }
          return Number(out);
        };
        const parts = hpText.split('/');
        const cur = parts.length > 1 ? digitsOf(parts[0]) : NaN;
        const max = parts.length > 1 ? digitsOf(parts[1]) : NaN;
        const low = max > 0 && cur / max < 0.45;
        if (low && click('itemBtn')) {
          const potion = document.querySelector('#moveSelectModal .move-btn');
          if (potion) { potion.click(); return; }
          click('closeMoveModalBtn');
        }
        // Mostly fight; occasionally try to catch, which is the point of the game.
        if (Math.random() < 0.2 && click('catchBtn')) {
          // Same reason as the move list: confirm in this step so the dimming
          // backdrop isn't what the pane shows for a whole tick.
          click('confirmCatchBtn');
          return;
        }
        // Open the move list and pick from it in the same step: showMoveSelect()
        // fills the modal synchronously, and leaving it open for a tick dims the
        // whole board behind its backdrop.
        if (click('moveSelectBtn')) {
          const moves = document.querySelectorAll('#moveSelectModal .move-btn');
          if (moves.length) moves[Math.floor(Math.random() * moves.length)].click();
        }
        return;
      }
      // Out of battle. A wiped team can't win anything, so start the run over
      // rather than leaving a dead screen up for the rest of the session.
      const status = (document.getElementById('statusText') ||
                      document.querySelector('.status-box') || {}).textContent || '';
      if (/all codemons fainted/i.test(status)) { location.reload(); return; }
      if (Math.random() < 0.25) { if (click('interactBtn')) return; }
      const ids = ['moveUpBtn','moveDownBtn','moveLeftBtn','moveRightBtn'];
      click(ids[Math.floor(Math.random() * ids.length)]);
    })()`,
  },
};
const PROFILE = PROFILES[process.env.DUNGEON_PROFILE || 'dungeon'] || PROFILES.dungeon;
const TICK_EVERY = Number(process.env.DUNGEON_TICK_FRAMES || 6);   // frames between ticks

const FPS = 8;
const CELL_ASPECT = 2.0;   // terminal cell height / width, in pixels

if (!PANE) { console.error('no pane id'); process.exit(1); }

// ---- herdr socket: one request per connection; herdr closes after replying.
function herdr(method, params) {
  return new Promise((resolve) => {
    const s = connect(SOCK);
    let buf = '';
    const done = (v) => { s.destroy(); resolve(v); };
    s.setTimeout(3000, () => done(null));
    s.on('error', () => done(null));
    s.on('data', (d) => {
      buf += d;
      if (buf.includes('\n')) { try { done(JSON.parse(buf)); } catch { done(null); } }
    });
    s.write(JSON.stringify({ id: 'dungeon', method, params }) + '\n');
  });
}

/**
 * Grow `clip` around its centre until it has the pane's shape. A crop shaped
 * differently from the pane gets letterboxed, and the bands are empty terminal
 * where the pane's shell prompt shows through. Growing the crop fills them with
 * the page around the game instead - nothing is cut off.
 */
function fitToPane(clip, size) {
  if (!size) return clip;
  const want = size.cols / (size.rows * CELL_ASPECT);      // pane width / height, in px
  let { x, y, width: w, height: h } = clip;
  if (w / h > want) {                                       // too wide: add height
    const nh = w / want; y -= (nh - h) / 2; h = nh;
  } else {                                                  // too tall: add width
    const nw = h * want; x -= (nw - w) / 2; w = nw;
  }
  return { x: Math.max(0, x), y: Math.max(0, y), width: w, height: h, scale: 1 };
}

async function paneSize() {
  const r = await herdr('pane.layout', { pane_id: PANE });
  const p = r?.result?.layout?.panes?.find((e) => e.pane_id === PANE);
  return p ? { cols: p.rect.width, rows: p.rect.height } : null;
}

// ---- Chrome over the DevTools pipe (fd 3 = to Chrome, fd 4 = from Chrome).
// Sweep profiles left by crashed runs, but not ones another pane's Chrome is using.
const live = (() => { try { return execSync('ps -axo args=').toString(); } catch { return null; } })();
if (live !== null) for (const d of readdirSync(tmpdir())) {
  if (d.startsWith('dungeon-chrome-') && !live.includes(d)) rmSync(join(tmpdir(), d), { recursive: true, force: true });
}
const profile = mkdtempSync(join(tmpdir(), 'dungeon-chrome-'));
const chrome = spawn(CHROME, [
  '--headless=new', '--remote-debugging-pipe', '--mute-audio',
  '--no-first-run', '--no-default-browser-check', '--disable-extensions',
  `--user-data-dir=${profile}`, '--window-size=1400,900', ...LEAN_FLAGS,
  ...(process.env.DUNGEON_CHROME_FLAGS || '').split(' ').filter(Boolean),
  'about:blank',
], { stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe'] });

let nextId = 1;
const pending = new Map();
let inbuf = Buffer.alloc(0);
chrome.stdio[4].on('data', (chunk) => {
  inbuf = Buffer.concat([inbuf, chunk]);
  let i;
  while ((i = inbuf.indexOf(0)) !== -1) {
    let msg;
    try { msg = JSON.parse(inbuf.subarray(0, i).toString()); } catch { msg = {}; }
    inbuf = inbuf.subarray(i + 1);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
    }
  }
});
function cdp(method, params = {}, sessionId) {
  const id = nextId++;
  const msg = { id, method, params };
  if (sessionId) msg.sessionId = sessionId;
  chrome.stdio[3].write(JSON.stringify(msg) + '\0');
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`${method} timed out`)); }, 5000);
    pending.set(id, {
      resolve: (v) => { clearTimeout(timer); resolve(v); },
      reject: (e) => { clearTimeout(timer); reject(e); },
    });
  });
}

let session = null;   // CDP session id, once the page is attached

// Copy the game's localStorage save out to SAVE_FILE (atomic write).
// No SAVE_KEY means the game keeps no state; nothing to copy.
async function persistSave() {
  if (!SAVE_KEY) return;
  if (!session) return;
  try {
    const { result } = await cdp('Runtime.evaluate', {
      returnByValue: true, expression: `localStorage.getItem(${JSON.stringify(SAVE_KEY)})`,
    }, session);
    if (typeof result.value !== 'string') return;
    writeFileSync(SAVE_FILE + '.tmp', result.value);
    renameSync(SAVE_FILE + '.tmp', SAVE_FILE);
  } catch { /* Chrome gone: keep the last good save */ }
}

let stopping = false;
async function shutdown() {
  if (stopping) return;
  stopping = true;
  await persistSave();
  await herdr('pane.graphics.clear', { pane_id: PANE, layer_id: LAYER });
  await new Promise((r) => {
    if (chrome.exitCode !== null || chrome.signalCode !== null) return r();
    chrome.once('exit', r);
    chrome.kill();
    setTimeout(() => { chrome.kill('SIGKILL'); r(); }, 2000);
  });
  rmSync(profile, { recursive: true, force: true });
  process.exit(0);
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
chrome.on('exit', shutdown);
chrome.on('error', shutdown);
chrome.stdio[3].on('error', shutdown);   // Chrome gone: writes to its pipe fail
chrome.stdio[4].on('error', shutdown);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const { targetInfos } = await cdp('Target.getTargets');
  const page = targetInfos.find((t) => t.type === 'page');
  const { sessionId } = await cdp('Target.attachToTarget', { targetId: page.targetId, flatten: true });
  session = sessionId;
  const S = (m, p) => cdp(m, p, sessionId);
  // Put the last save into localStorage before the game's scripts run.
  let save = null;
  try { save = SAVE_KEY ? readFileSync(SAVE_FILE, 'utf8') : null; if (save) JSON.parse(save); } catch { save = null; }
  if (save) {
    await S('Page.addScriptToEvaluateOnNewDocument', {
      source: `try { localStorage.setItem(${JSON.stringify(SAVE_KEY)}, ${JSON.stringify(save)}); } catch (e) {}`,
    });
  }
  // Desktop-width layout so the three columns don't stack.
  // Match the emulated viewport to the pane's shape instead of a fixed 1400x900.
  // A tall narrow pane showing a wide page letterboxes badly - most of the pane
  // ends up empty. Laying the page out at the pane's aspect lets it fill.
  const paneNow = await paneSize();
  let vw = 1400, vh = 900;
  if (paneNow) {
    const aspect = (paneNow.cols) / (paneNow.rows * CELL_ASPECT);   // w/h in pixels
    const AREA = 1400 * 900;                                        // keep the pixel budget
    vw = Math.round(Math.sqrt(AREA * aspect));
    vh = Math.round(AREA / vw);
    vw = Math.min(2200, Math.max(700, vw));
    vh = Math.min(2200, Math.max(600, vh));
  }
  if (process.env.DUNGEON_VIEWPORT) {                 // debugging: force a size
    [vw, vh] = process.env.DUNGEON_VIEWPORT.split('x').map(Number);
  }
  await S('Emulation.setDeviceMetricsOverride',
          { width: vw, height: vh, deviceScaleFactor: 1, mobile: false });
  await S('Page.enable');
  // Tall pane: ask the game for its portrait layout. Games that don't know the
  // parameter just ignore it.
  const tall = vh > vw;
  await S('Page.navigate', { url: 'file://' + GAME + (tall ? '?portrait=1' : '') });
  for (let i = 0; i < 50; i++) {                                     // up to ~10 s
    const { result: ready } = await S('Runtime.evaluate', {
      returnByValue: true, expression: PROFILE.ready,
    });
    if (ready.value) break;
    await sleep(200);
  }
  await sleep(500);                                                   // let fonts settle

  // Crop to the play area: zone name + AI status + canvas (skip the controls hint).
  // A profile whose selectors don't match would give an undefined rect, and
  // captureScreenshot answers "Invalid parameters" to that. Fall back to the
  // viewport rather than dying.
  const getClip = async () => {
    const { result } = await S('Runtime.evaluate', {
      returnByValue: true, expression: process.env.DUNGEON_CLIP || PROFILE.clip,
    });
    const rect = result?.value;
    return (rect && rect.width > 0 && rect.height > 0)
      ? { ...rect, scale: 1 }
      : { x: 0, y: 0, width: 1400, height: 900, scale: 1 };
  };
  let clip = await getClip();

  let size = await paneSize();
  let frame = 0;
  let deadSince = 0;
  let failures = 0;                                                   // herdr misses in a row
  while (!stopping && size && failures < 3) {
    const t0 = Date.now();
    if (frame % (FPS * 2) === 0) {                                    // follow resizes
      const s = await paneSize();
      if (s) size = s; else failures++;
    }

    if (PROFILE.dead) {
      const { result: dead } = await S('Runtime.evaluate', {
        returnByValue: true, expression: PROFILE.dead,
      });
      if (dead.value) {
        deadSince ||= Date.now();
        if (Date.now() - deadSince > 2500) {
          await S('Runtime.evaluate', { expression: PROFILE.revive });
          deadSince = 0;
        }
      } else deadSince = 0;
    }
    if (PROFILE.tick && frame % TICK_EVERY === 0) {
      const r = await S('Runtime.evaluate', { expression: PROFILE.tick, returnByValue: true });
      if (process.env.DUNGEON_DEBUG && r?.exceptionDetails) {
        console.error('tick threw:', JSON.stringify(r.exceptionDetails).slice(0, 400));
      }
    }

    if (PROFILE.dynamicClip) clip = await getClip();   // battle vs board
    const shot = fitToPane(clip, size);
    if (process.env.DUNGEON_DEBUG && frame % (FPS * 3) === 0) {   // layout probe
      const { result: m } = await S('Runtime.evaluate', { returnByValue: true, expression: `(() => {
        const c = document.querySelector('.canvas-container'), v = document.querySelector('canvas#gameCanvas') || document.querySelector('canvas');
        const cr = c && c.getBoundingClientRect(), vr = v && v.getBoundingClientRect();
        return { container: cr && Math.round(cr.height), canvas: vr && Math.round(vr.height),
                 canvasBitmap: v && [v.width, v.height], vp: [innerWidth, innerHeight] };
      })()` });
      console.error('layout', JSON.stringify({ ...m?.value, clipH: Math.round(clip.height) }));
    }
    // captureBeyondViewport: the crop can run past the bottom of the viewport
    // (a portrait map under stacked side panels), and without this Chrome leaves
    // everything below the fold blank - the lower half of the map, hero included.
    const { data } = await S('Page.captureScreenshot',
                             { format: 'png', clip: shot, captureBeyondViewport: true });
    if (process.env.DUNGEON_DUMP) writeFileSync(process.env.DUNGEON_DUMP, Buffer.from(data, 'base64'));

    // Fit the image inside the pane, keeping its shape.
    let cols = size.cols;
    let rows = Math.round((cols * shot.height) / shot.width / CELL_ASPECT);
    if (rows > size.rows) {
      rows = size.rows;
      cols = Math.round((rows * CELL_ASPECT * shot.width) / shot.height);
    }
    const r = await herdr('pane.graphics.set', {
      pane_id: PANE, format: 'png',
      image_width: Math.round(shot.width), image_height: Math.round(shot.height),
      data_base64: data,
      placement: {
        viewport_row: Math.max(0, Math.floor((size.rows - rows) / 2)),
        viewport_col: Math.max(0, Math.floor((size.cols - cols) / 2)),
        grid_cols: cols, grid_rows: rows,
      },
      z_index: 10, layer_id: LAYER,
    });
    if (r?.error) break;                                               // pane closed
    failures = r ? 0 : failures + 1;                                  // herdr gone?

    frame++;
    if (frame % (FPS * 5) === 0) await persistSave();                  // every ~5 s
    await sleep(Math.max(0, 1000 / FPS - (Date.now() - t0)));
  }
  await shutdown();
}

main().catch(async (e) => { console.error(e); await shutdown(); });
