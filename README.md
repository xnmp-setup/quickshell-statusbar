# quickshell-statusbar

A Quickshell status bar for Hyprland: workspace chips with per-window
application icons and live Claude/Codex agent state, system telemetry with
hover sparklines, and AI quota cells for Claude Code and Codex.

Extracted from a chezmoi dotfiles repository with full history.

## Layout

- `quickshell/` — the Quickshell/QML configuration (`shell.qml` entry point).
- `bin/` — executables expected on `PATH` at `~/.local/bin`:
  - `hypr-status-stream` — emits JSON metric/workspace snapshots every second.
  - `ai-usage-stream` — emits normalized Claude/Codex quota usage.
  - `rename-hypr-workspace` — inline workspace rename helper used by the bar.
- `lib/` — Python sources for the streams, run via `uv run --script`;
  expected at `~/.local/lib`.
- `tests/` — Python, QML, and shell test suites.

## Deployment

Deployed by chezmoi as a `git-repo` external cloned to
`~/.local/share/quickshell-statusbar`, with symlinks:

- `~/.config/quickshell/statusbar` → `quickshell/`
- `~/.local/bin/{hypr-status-stream,ai-usage-stream,rename-hypr-workspace}` → `bin/…`
- `~/.local/lib/{hypr_status_stream,ai_usage_stream,ghostty_status}.py` → `lib/…`

Run with:

```sh
qs -d -p ~/.config/quickshell/statusbar
```

## Dependencies

- Quickshell (Qt 6) on Hyprland/Wayland.
- `uv` at `~/.local/bin/uv` for the Python streams.
- Hack Nerd Font for the Wi-Fi/battery icon cells; cells fall back to text
  labels when the font is missing.
- The WezTerm agent lifecycle hook (`wezterm-agent-status`) lives with the
  WezTerm configuration in the dotfiles repository; this bar only reads the
  runtime state files it writes under `$XDG_RUNTIME_DIR`.

## Tests

```sh
uv run python -m unittest tests.test_hypr_status_stream tests.test_ai_usage_stream
QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/tst_statusbar.qml -o -,txt
sh tests/rename-hypr-workspace.test.sh
```
