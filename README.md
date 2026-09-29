# herdr game pane

Something to look at while Claude Code works, so this plays one of my browser games in a side pane of [herdr](https://herdr.dev) (a terminal multiplexer) for as long as Claude is busy.

You send Claude a message and a pane opens on the right with a game playing itself. When Claude finishes, the pane closes. The two games are my [dungeon crawler](https://github.com/bryanfrds/dragons-dungeon-game) and [CodeMon](https://github.com/bryanfrds/Codemon), and they take turns: dungeon one message, CodeMon the next.

## What happens on each message

1. Claude Code runs `start.sh` through its `UserPromptSubmit` hook.
2. `start.sh` splits the current herdr pane to open one on the right, and picks which game is up.
3. It starts `dungeon.mjs` in the background, pointed at the new pane.
4. When Claude stops, the `Stop` hook runs `stop.sh`. That kills the renderer, clears the image off the pane, and closes it.

Everything is tracked per pane, so if you've got several Claude sessions open in herdr, each one gets its own game and closing one doesn't touch the others.

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
- `play.sh`: starts a game whenever you want one, not just while Claude works. `play.sh codemon`, `play.sh dungeon`, or `play.sh stop`.
- `bounce.py`: an older, lighter mode that bounces a sprite around the pane instead of running a game. It needs PNGs in `sprites/`, which aren't in the repo.

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
