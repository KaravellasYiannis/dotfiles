#!/bin/bash

pane_id="$1"

cmd=$(tmux display-message -p -t "$pane_id" '#{pane_current_command}')
path=$(tmux display-message -p -t "$pane_id" '#{b:pane_current_path}')

case "$cmd" in
    *opencode*|*codex*|*copilot*)
        echo "[$path]";;
    ssh)
        echo "\@$path" ;;
    *)
        echo "$path";;
esac
