# Dotfiles: Omarchy customization

## Goal

This branch tracks a small personal configuration on top of an existing Omarchy
installation. Omarchy supplies the desktop and application defaults; this repo
keeps selected configurations editable and version-controlled.

Keep it simple. Do not recreate the old standalone desktop setup, add a dotfile
framework, or introduce layers of configuration just to avoid tracking whole
files. Prefer Omarchy defaults and a few deliberate personal changes.

## Layout and symlink direction

`home/` mirrors paths relative to `$HOME`. Actual configuration contents live
inside this repository; their normal locations point back here:

```text
~/.bashrc                 -> <repo>/home/.bashrc
~/.config/tmux/tmux.conf   -> <repo>/home/.config/tmux/tmux.conf
~/.config/nvim            -> <repo>/home/.config/nvim
~/.config/hypr/bindings.lua -> <repo>/home/.config/hypr/bindings.lua
```

Git tracks these real files, not links pointing out to home-directory files.
Editing through either path changes the same contents. Treat repo edits as live
configuration changes when these links are installed.

## What setup.sh does

`./setup.sh` is an **import-and-link script**, not a fresh-machine deployment
script. It assumes Omarchy and the selected live configurations already exist.

- `FILES` is the single list of managed paths, relative to `$HOME`. Add a file
  or directory there to expand the scope; avoid additional configuration formats.
- It checks that every listed live path exists before importing anything.
- Entries already symlinked to the correct repository location are skipped.
- For other entries, it captures the live contents, backs up the existing repo
  entry and original home entry, installs the captured contents under `home/`,
  and links the home location to the repo.
- Backups live outside Git under `~/.local/state/dotfiles-backup.*`.
- Imported root `.git` metadata is moved into the backup rather than creating
  a nested repository.
- The Neovim theme link is repaired after the import loop, even if Neovim was
  already linked.

Running this script on another machine imports that machine's configurations;
it does not install this repository's saved preferences there. Do not silently
reverse this behavior. Do not run it merely to test a change: use a temporary
home and a copied script for tests.

The old Stow/package installer instructions still present in `README.md` are
legacy instructions, not the workflow for this branch.

## Configuration ownership

### Bash

`home/.bashrc` retains Omarchy's environment bootstrap and shared Bash defaults.
Personal aliases and prompt overrides come afterward. The prompt intentionally
uses `~/.local/bin/bashline` instead of Starship:

```bash
unset PROMPT_COMMAND PS0
PROMPT_COMMAND='PS1="$("$HOME/.local/bin/bashline" "$?")"'
```

Keep the non-interactive-shell guard and bootstrap ordering intact.

### tmux

`home/.config/tmux/tmux.conf` is a tracked copy of Omarchy's defaults with personal
changes at the bottom, including the `allmux` popup. It does not dynamically
source the packaged tmux configuration. New upstream defaults therefore require
review and incorporation; Git tracking does not automatically merge updates.

Reload with `tmux source-file ~/.config/tmux/tmux.conf` or the default prefix
followed by `q`. Avoid restarting the tmux server or closing sessions.

### Neovim

Use Omarchy's upstream LazyVim-based setup, not the previous standalone Neovim
configuration. Keep Omarchy's clipboard and theme integration.

Personal plugin additions and overrides currently live together in
`home/.config/nvim/lua/plugins/init.lua`: Neogit, CodeDiff, the `<leader>gg`
Neogit mapping, and disabling LazyVim's `mini.pairs` autopairing plugin.
Use LazyVim extension points for further changes rather than replacing its
bootstrap. Keep `lazy-lock.json` and `lazyvim.json` tracked.

**Exception: `lua/plugins/theme.lua` is machine-local and ignored by Git.**
`setup.sh` makes it an absolute symlink to
`$HOME/.local/state/omarchy/current/theme/neovim.lua`. This allows Omarchy's theme
selector to control Neovim without generating Git changes on every theme switch.

Do not commit the resolved contents or hardcode a colorscheme in that file.
The importer uses `cp -aL`, which dereferences links; the explicit repair is
necessary to avoid freezing the selected theme. Omarchy's original relative
link is also unsuitable once the config physically lives in this repo.
Check for similar generated files or relative-link assumptions when expanding
the managed paths.

### Hyprland keybindings

Only `home/.config/hypr/bindings.lua` is managed, not the whole Hyprland directory.
It contains personal overrides loaded after Omarchy's defaults. Preserve existing
overrides and unbind conflicting defaults before adding replacements. After edits,
run `hyprctl reload` followed by `hyprctl configerrors` and resolve any errors.

### Personal executables and excluded configuration

`home/.local/bin/` contains `bashline`, `allmux`, and `aimux`. The setup script
does not currently deploy them. If deployment is added, link executables
individually into `~/.local/bin`; do not replace the entire directory, which may
also contain files installed by other applications. This is repo-to-home
deployment, unlike the configuration import loop.

OpenCode configuration is intentionally outside this repo. `~/.config/opencode`
is a real local directory, not a repo symlink. Do not reintroduce it into `FILES`
or Git unless explicitly requested.

## Safety and validation

- For Omarchy desktop or system customization, use the Omarchy skill and its
  relevant topic guide. Never edit packaged files under `/usr/share/omarchy/`.
- Preserve unrelated user changes and back up live configs before replacing them.
- Do not run refresh/reset commands, install packages, or restart services unless
  required and authorized. Omarchy refreshes may overwrite symlink targets.
- Keep generated state, caches, credentials, and machine-specific links out of Git.
- Validate shell edits with `bash -n setup.sh` and `bash -n home/.bashrc`.
- Test setup imports, backups, repeat runs, and theme-link repair in isolation.
- After theme changes, a headless Neovim check can inspect `vim.g.colors_name`;
  avoid broad plugin updates or cleanup just to validate a small config change.
- Do not commit or push unless requested.
