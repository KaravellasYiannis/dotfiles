# Dotfiles

## Omarchy configs

Run `./setup.sh` to import your current Bash, tmux, and Neovim configurations
into `home/` and symlink their original locations back to this repository.
Existing files on both sides are backed up under `~/.local/state/dotfiles-backup.*`.
Already-linked entries are skipped on subsequent runs.

Neovim's `lua/plugins/theme.lua` is intentionally untracked. `setup.sh` links it
to the active Omarchy theme so theme changes keep working without Git diffs.

Add paths relative to your home directory to the `FILES` array in `setup.sh`
to track more files or directories. This imports your live configuration; it
does not deploy the repository's existing configuration onto another machine.
Use this instead of the full Stow installer below for the Omarchy-only setup.

## Install

```bash
cd ~/devel/environment/packages
./install

cd ~/devel/environment
./install
```
