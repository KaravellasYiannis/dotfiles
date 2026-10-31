#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Paths relative to $HOME. Add files or whole directories here.
FILES=(
  .bashrc
  .config/tmux/tmux.conf
  .config/nvim
  .config/ghostty/config
  .config/hypr/bindings.lua
  .config/hypr/input.lua
)

for file in "${FILES[@]}"; do
  if [[ ! -e "$HOME/$file" ]]; then
    echo "Missing configuration: $HOME/$file" >&2
    exit 1
  fi
done

BACKUP=""
ensure_backup() {
  if [[ -z "$BACKUP" ]]; then
    mkdir -p "$HOME/.local/state"
    BACKUP="$(mktemp -d "$HOME/.local/state/dotfiles-backup.XXXXXX")"
    echo "Backups: $BACKUP"
  fi
}

for file in "${FILES[@]}"; do
  source="$HOME/$file"
  target="$REPO/home/$file"

  if [[ -L "$source" && "$(readlink -f -- "$source")" == "$target" ]]; then
    echo "Already linked: $file"
    continue
  fi

  ensure_backup

  mkdir -p "$BACKUP/import/$(dirname "$file")" \
    "$BACKUP/repo/$(dirname "$file")" \
    "$BACKUP/home/$(dirname "$file")" "$(dirname "$target")"

  # Copy first so existing symlinks cannot lose their contents during the move.
  cp -aL -- "$source" "$BACKUP/import/$file"
  if [[ -e "$target" || -L "$target" ]]; then
    mv -- "$target" "$BACKUP/repo/$file"
  fi
  mv -- "$source" "$BACKUP/home/$file"
  mv -- "$BACKUP/import/$file" "$target"

  # Keep imported configurations in this Git repository, not nested repositories.
  if [[ -e "$target/.git" ]]; then
    mkdir -p "$BACKUP/git/$(dirname "$file")"
    mv -- "$target/.git" "$BACKUP/git/$file"
  fi

  ln -s -- "$target" "$source"
  echo "Linked: $file"
done

# This generated theme must follow Omarchy, not a snapshot stored in Git.
# Use an absolute link because the Neovim directory lives inside this repo.
THEME="$REPO/home/.config/nvim/lua/plugins/theme.lua"
CURRENT_THEME="$HOME/.local/state/omarchy/current/theme/neovim.lua"
if [[ ! -L "$THEME" || "$(readlink -- "$THEME")" != "$CURRENT_THEME" ]]; then
  if [[ -e "$THEME" || -L "$THEME" ]]; then
    ensure_backup
    mv -- "$THEME" "$BACKUP/nvim-theme.lua"
  fi
  mkdir -p "$(dirname "$THEME")"
  ln -s -- "$CURRENT_THEME" "$THEME"
  echo "Linked Neovim theme to Omarchy"
fi
