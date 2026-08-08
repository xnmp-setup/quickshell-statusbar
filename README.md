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
- `~/.local/lib/{hypr_status_stream,ai_usage_stream,ghostty_status,stream_kit}.py` → `lib/…`

`stream_kit.py` is the shared infrastructure toolkit both streams import. Its
`~/.local/lib` symlink is optional for imports (Python resolves a script
symlink to its real directory, the clone's `lib/`), but the file must exist in
the deployed clone — a checkout without it breaks both `bin/` streams at
startup with `ModuleNotFoundError`.

Run with:

```sh
qs -d -p ~/.config/quickshell/statusbar
```

## Dependencies

- Quickshell (Qt 6) on Hyprland/Wayland.
- `uv` at `~/.local/bin/uv` for the Python streams.
- Hack Nerd Font for the Wi-Fi/battery icon cells; cells fall back to text
  labels when the font is missing.
- `mako` for the Focus (do-not-disturb) cell, with a `[mode=do-not-disturb]`
  `invisible=1` section in its config so the mode actually silences
  notifications. The cell toggles `makoctl mode -t do-not-disturb` (also
  reachable as `qs ipc call bar toggleFocus`) and shows an unreachable state
  when mako is missing.
- The WezTerm agent lifecycle hook (`wezterm-agent-status`) lives with the
  WezTerm configuration in the dotfiles repository; this bar only reads the
  runtime state files it writes under `$XDG_RUNTIME_DIR`.

## Tests

```sh
uv run python -m unittest discover -s tests -p 'test_*.py'
QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -input tests/tst_statusbar.qml \
  -import "$PWD/tests/stubs" -platform offscreen
sh tests/rename-hypr-workspace.test.sh
```

The QML suite needs the **Qt 6** `qmltestrunner` (the one on `PATH` is often
Qt 5, which fails silently) and `QML_XHR_ALLOW_FILE_READ=1` so the contract
tests can read `tests/fixtures/stream_contract.json`. `tests/stubs/` holds a
stand-in for the Quickshell QML module, whose C++ plugin only loads inside the
`quickshell` binary.

`tests/fixtures/stream_contract.json` pins the Python→QML wire contract from
both ends: `tests/test_stream_contract.py` proves the streams emit its exact
structure, and `tests/tst_statusbar.qml` proves `StatusSanitizer.js` accepts it
unchanged — neither side can drift alone.
