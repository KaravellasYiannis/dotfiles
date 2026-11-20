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
