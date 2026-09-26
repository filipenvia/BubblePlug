#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT_DIR="$HOME/Library/Application Support/PlugSpot"
REMOTE_DIR="$HOME/Music/Ableton/User Library/Remote Scripts/PlugSpot"
mkdir -p "$SUPPORT_DIR" "$REMOTE_DIR"
chmod 700 "$SUPPORT_DIR"
cp -R "$ROOT_DIR/remote_script/PlugSpot/." "$REMOTE_DIR/"
"$ROOT_DIR/macos/configure-launcher.sh"
cat <<MSG
Installed Ableton Remote Script at:
  $REMOTE_DIR
Installed export worker and lifecycle launcher under:
  $SUPPORT_DIR

Restart Ableton Live once to load the updated launcher. Future exports will
validate first, ask before replacing global Collections, wait for Live to close,
back up its files, apply the export, and reopen Live.
MSG
