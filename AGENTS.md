# Dotfiles: Omarchy customization

Omarchy supplies the base system. This repo owns the personal files in `home/`,
which mirrors paths relative to `$HOME`. Keep it simple: no package bootstrap,
dotfile framework, or unnecessary layers.

`./install` uses GNU Stow to link files from the repo into `$HOME` without
folding directories.
Leave conflict handling to Stow; never adopt live files or automatically
overwrite them. Back up and reconcile conflicts manually. Test deployment in a
temporary home under `/tmp`, never by installing to the live home. Do not add
test files to this repo.

## Configuration ownership

- **Bash:** Preserve Omarchy's environment bootstrap and the non-interactive
  guard. Keep the `bashline` prompt and history behavior.
- **Ghostty:** Preserve the dynamic Omarchy theme include. Deploy the shader.
- **tmux:** The tracked config is standalone. Keep the Aimux status and pane
  hooks; reload with `tmux source-file ~/.config/tmux/tmux.conf` instead of
  restarting the server.
- **Neovim:** Keep the LazyVim setup, Omarchy clipboard integration, and tracked
  lockfiles. The generated `lua/plugins/theme.lua` link belongs in the live
  Neovim directory and points to `$HOME/.local/state/omarchy/current/theme/neovim.lua`.
  Do not track or deploy it.
- **Hyprland:** Manage only the personal files under `home/`, not the entire
  live Hyprland directory. Preserve existing overrides and unbind conflicting
  defaults before adding replacements.
- **Aimux:** Deploy just the tracked executables, adapters and registration
  files. Don't add entire agent config directories, credentials, or state.

## Safety and validation

- Treat edits to linked files as live changes. Use the Omarchy skill for
  desktop customization and never edit packaged files under `/usr/share/omarchy/`.
- Preserve unrelated changes and back up live files before replacing them.
  Don't run refresh/reset commands, install packages, or restart services
  unless required and authorized. Refreshes can overwrite symlink targets.
- Keep generated state, caches, credentials, and machine-specific links out of Git.
- Validate shell edits with `bash -n install` and `bash -n home/.bashrc`.
  After Hyprland config edits, run `hyprctl reload` and `hyprctl configerrors`.
- Do not commit or push unless requested.
