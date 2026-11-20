# Dotfiles

## Omarchy configs

Run `./setup.sh` to import your current Bash, tmux, Neovim, Ghostty, and Hyprland keybinding configurations
into `home/` and symlink their original locations back to this repository.
Existing files on both sides are backed up under `~/.local/state/dotfiles-backup.*`.
Already-linked entries are skipped on subsequent runs.

Neovim's `lua/plugins/theme.lua` is intentionally untracked. `setup.sh` links it
to the active Omarchy theme so theme changes keep working without Git diffs.

Add paths relative to your home directory to the `FILES` array in `setup.sh`
to track more files or directories. This imports your live configuration; it
does not deploy the repository's existing configuration onto another machine.
Ghostty's cursor shader is deployed separately: run `./install` to link
`~/.config/ghostty/shaders/cursor_smear.glsl` to its copy in `home/`.
Existing shader files are backed up; repeat runs are safe. The shader license
is kept in the repository but is not installed.

## Install

Run `./setup.sh` to import live configurations, then `./install` to deploy
the cursor shader. Neither script installs packages.

## aimux

Run `./install aimux` to build aimux from `~/devel/aimux` (or `$AIMUX_SOURCE`).
The executable in `~/.local/bin` is built from source, not copied from the
binary tracked here. The installer requires Go and `jq`, preserves the existing
OpenCode settings, and backs up changed files under
`~/.local/state/dotfiles-backup.*`. Reload tmux with `Prefix+q` after installation.

- `Prefix+a`: aimux agent dashboard. `Prefix+f`: the existing `allmux` picker.
- The tmux tab shows `[directory ▶]` when its active pane is working, `!` when
  blocked, `✓` for unread output, or `○` when idle. Focusing a pane acknowledges
  unread output but doesn't clear a pending approval or question.
- Run OpenCode normally. Codex is not tracked by aimux.
- Start Copilot as `copilot --experimental` so it loads the aimux extension.
  Copilot CLI 1.0.114 and Node.js are required for this integration.
