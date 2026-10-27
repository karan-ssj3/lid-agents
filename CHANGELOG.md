# Changelog

## 1.0.0

First release.

- **Menu bar app**: a coffee cup that fills in (with the number of busy agents) while closing the lid keeps agents running. Click it to switch, see which agents are busy, open the log, or turn off Open at Login.
- **Global hotkey** ⌃⌥⌘A to switch, configurable with `defaults write io.github.liam-machine.lid-agents Hotkey "ctrl+opt+cmd+l"`. No Accessibility permission needed.
- **Agent-aware by default**: stays awake only while an agent is busy (Claude Code's own `caffeinate`, or CPU use for Codex, Gemini CLI, Aider, opencode, Amp, Goose, Cursor Agent, Droid), then pauses again after 3 idle minutes and puts a closed Mac to sleep.
- **Safety limits**: an 8-hour cap and a 15% battery floor, both adjustable.
- **`agents` command** for the terminal: `keep`, `pause`, `toggle`, `busy`, status, `uninstall`.
- **One-line installer** that asks for your password once, for a sudoers rule allowing only `pmset -a disablesleep 0|1`.

Install:

```bash
curl -fsSL https://github.com/liam-machine/lid-agents/releases/latest/download/install.sh | bash
```
