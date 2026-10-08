# herdr game pane

Something to look at while Claude Code works, so this plays one of my browser games in a side pane of [herdr](https://herdr.dev) (a terminal multiplexer) for as long as Claude is busy.

You send Claude a message and a pane opens on the right with a game playing itself. When Claude finishes, the pane closes. The two games are my [dungeon crawler](https://github.com/bryanfrds/dragons-dungeon-game) and [CodeMon](https://github.com/bryanfrds/Codemon), and they take turns: dungeon one message, CodeMon the next.

## What happens on each message

1. Claude Code runs `start.sh` through its `UserPromptSubmit` hook.
2. `start.sh` splits the current herdr pane to open one on the right, and picks which game is up.
3. It starts `dungeon.mjs` in the background, pointed at the new pane.
4. When Claude stops, the `Stop` hook runs `stop.sh`. That kills the renderer, clears the image off the pane, and closes it.

Everything is tracked per pane, so if you've got several Claude sessions open in herdr, each one gets its own game and closing one doesn't touch the others.

Working out which pane a chat is in is less obvious than it sounds. Claude Code keeps spare processes warm in the background and hands one to the next chat you open, and a spare keeps the herdr pane id of wherever it was started. So `$HERDR_PANE_ID` can point at a different chat's pane. The hooks ask herdr which pane is showing their session instead, and only fall back to `$HERDR_PANE_ID` for a chat that didn't come from a spare. Before this, games kept opening beside an idle chat while the one actually working got nothing.

The games alternate strictly instead of at random. I tried a coin flip first, but three dungeons in a row just looked like CodeMon was broken. If one game's folder is missing, it plays the other one.

## How the game gets into a terminal

`dungeon.mjs` opens a headless Chrome, loads the game's `index.html`, and screenshots it about 8 times a second. Each screenshot goes to the pane through herdr's graphics API, over its unix socket.

- **Dungeon:** the game already plays itself. The script just presses respawn when the hero dies.
- **CodeMon:** the script drives it, walking around, starting fights and picking moves. During a fight it crops to the battle screen so the fight fills the pane. The rest of the time it shows the whole board.

A few things that were fiddly to get right:

- **Window size:** the browser window is sized to the pane, so the game lays itself out for it. A tall, narrow pane gets a tall layout, not a squashed wide one.
- **Crop shape:** the screenshot is cropped to the pane's exact shape. If the shapes don't match, herdr letterboxes the image, and the shell prompt shows through the gaps.
- **Below the window:** it captures past the bottom of the browser window. Without that, the bottom of a tall dungeon map came out blank and the hero kept vanishing off the edge.
- **Memory:** Chrome runs with most of its background features switched off and a small JavaScript heap, so each game uses a lot less memory than a normal tab.

## Saves

Chrome's profile is thrown away every run, so the dungeon's save is copied out to `saves/` and put back next time. Each Claude chat gets its own save, keyed by the chat's session id, so resuming a chat brings back the same hero. CodeMon currently starts fresh each time in the pane.

## Files

- `dungeon.mjs`: streams a game into a pane. Despite the name, it handles both games; each has a profile near the top of the file saying how to tell it's loaded, what to crop, and how to keep it moving.
- `start.sh` / `stop.sh`: the two Claude Code hooks.
- `pane-for-session.sh`: finds the herdr pane a Claude session is really in (see above).
- `play.sh`: starts a game whenever you want one, not just while Claude works. `play.sh codemon`, `play.sh dungeon`, or `play.sh stop`.
- `bounce.py`: an older, lighter mode that bounces a sprite around the pane instead of running a game. It needs PNGs in `sprites/`, which aren't in the repo.
- `pr-popup.sh`: an optional extra, not part of the game pane. When a `pr-reviewer` subagent finishes, it shows a small card at the bottom of the screen with a sound: `green-fn-cropped.png` and `green-fn.mp3` for an approval (taking turns with `green-fn-video.mov`, a clip with a see-through background that plays with its own sound, at 30% volume; `GREEN_FN=image` or `GREEN_FN=video` picks one), `thanos.gif` and `fahhh.mp3` for requested changes (taking turns with `fail-video.mp4`, shown as a rounded card with its own sound; `THANOS=image` or `THANOS=video` picks one). Videos play at 30% volume; `POPUP_VOLUME` sets 0-1. Those files are your own and aren't in the repo; without the image it does nothing. Hook it up as a `SubagentStop` hook (`bash ~/.claude/runner/pr-popup.sh`), and try it with `pr-popup.sh --show green` or `--show fail`. macOS only.
- `tests/`: tests for the hook scripts (see Tests below).

## Setup

You need herdr, Node, and either Google Chrome or Playwright's headless shell. The headless shell is used if it's installed, since it's lighter. With no browser at all, it falls back to the bouncing sprite.

Clone this to `~/.claude/runner`, then add the hooks to `~/.claude/settings.json`:

```json
"hooks": {
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/runner/start.sh" }] }],
  "Stop":             [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/runner/stop.sh" }] }]
}
```

The games are expected at `~/pixel-dungeon-crawler` and `~/pokemon-wannabe`. The hooks only do anything inside herdr; in any other terminal they exit straight away.

## Settings

All of these are environment variables:

| Variable | What it does |
|---|---|
| `RUNNER_GAME` | `codemon` or `dungeon` to always play that one game |
| `RUNNER_MODE` | `overlay` bounces the sprite over the Claude pane; `pane` bounces it in a side pane |
| `DUNGEON_GAME` | path to a different game's `index.html` |
| `DUNGEON_CHROME` | path to a specific Chrome binary |
| `DUNGEON_DEBUG` | `1` logs layout info and any errors from the auto-player |

## If something's off

- **No pane appears:** check you're inside herdr (`echo $HERDR_PANE_ID` should print something) and that the hooks are in `settings.json`.
- **The pane opens but stays blank:** run `DUNGEON_DEBUG=1 node dungeon.mjs <pane id>` by hand to see what it's complaining about.
- **Leftover panes:** they get closed the next time you message Claude. `play.sh stop` closes one started by `play.sh`.

## Tests

```bash
bash tests/test_scripts.sh
```

GitHub runs them on Linux and macOS for every pull request.

They run the hook scripts against a fake `herdr` and `node` in a throwaway home folder, so no real pane opens and no save is touched. They cover finding the chat's real pane, taking turns between the games, keeping one dungeon save per chat, not stacking a second game, cleaning up a pane a crashed run left behind, and closing only your own pane on stop.
