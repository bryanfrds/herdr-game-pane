# herdr game pane

Plays a browser game in a side pane while Claude Code works. It uses [herdr](https://herdr.dev), the terminal multiplexer.

When you send Claude a message, a pane opens on the right and a game starts playing itself in it. When Claude finishes, the pane closes. The games it runs are my [dungeon crawler](https://github.com/bryanfrds/dragons-dungeon-game) and [CodeMon](https://github.com/bryanfrds/Codemon), taking turns.

## How it works

`dungeon.mjs` starts a headless Chrome, loads the game, and takes a screenshot about 8 times a second. It sends each one to the pane through herdr's graphics API. The dungeon plays itself, so the script only presses respawn when the hero dies. CodeMon can't play itself, so the script clicks its buttons for it.

Some details that took a while to get right:

- The browser window is sized to match the pane, so the game lays itself out to fit. A tall pane gets a tall layout.
- The screenshot is cropped to the pane's exact shape, so it fills the pane and hides the shell prompt behind it.
- It captures below the bottom of the browser window too. Without that, the bottom of a tall map came out blank.

## Files

- `dungeon.mjs` streams a game into a pane
- `start.sh` / `stop.sh` are the Claude Code hooks that open and close the pane each turn
- `play.sh` starts a game whenever you want one: `play codemon`, `play dungeon`, `play stop`
- `bounce.py` is an older, lighter mode that bounces a sprite around instead of running a game. It needs PNGs in `sprites/`, which aren't included here.

## Setup

Needs herdr, Node, and Chrome (or Playwright's headless shell). Add the hooks to `~/.claude/settings.json`:

```json
"hooks": {
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/runner/start.sh" }] }],
  "Stop":             [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/runner/stop.sh" }] }]
}
```

The games are expected at `~/pixel-dungeon-crawler` and `~/pokemon-wannabe`. You can point it somewhere else with `DUNGEON_GAME`.

Useful environment variables:

- `RUNNER_GAME=codemon` or `dungeon` always runs that one game
- `RUNNER_MODE=overlay` switches to the bouncing sprite instead
- `DUNGEON_DEBUG=1` logs layout info and any errors from the auto-player
