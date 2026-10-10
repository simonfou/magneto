#!/bin/sh
# Launch the visualizer (Spotify gets wired in automatically).
exec "$HOME/.local/bin/godot" --path "$(dirname "$(readlink -f "$0")")" "$@"
