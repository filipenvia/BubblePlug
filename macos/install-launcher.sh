#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT_DIR="$HOME/Library/Application Support/BubblePlug"
NEW_CACHE_DIR="$HOME/Library/Caches/BubblePlug"
mkdir -p "$SUPPORT_DIR" "$NEW_CACHE_DIR"
chmod 700 "$SUPPORT_DIR"
USER_LIBRARIES=("${(@f)$(/usr/bin/python3 "$ROOT_DIR/macos/ableton-user-libraries.py" "$HOME")}")
INSTALLED_LIBRARIES="$SUPPORT_DIR/installed-user-libraries.txt"
: > "$INSTALLED_LIBRARIES"
for USER_LIBRARY in "${USER_LIBRARIES[@]}"; do
  [[ -n "$USER_LIBRARY" ]] || continue
  if [[ "$USER_LIBRARY" == /Volumes/* && ! -d "$USER_LIBRARY" ]]; then
    print -u2 "Skipping unavailable Ableton User Library: $USER_LIBRARY"
    continue
  fi
  REMOTE_DIR="$USER_LIBRARY/Remote Scripts/BubblePlug"
  mkdir -p "$REMOTE_DIR"
  cp -R "$ROOT_DIR/remote_script/BubblePlug/." "$REMOTE_DIR/"
  print -r -- "$USER_LIBRARY" >> "$INSTALLED_LIBRARIES"
done
"$ROOT_DIR/macos/configure-launcher.sh"
cat <<MSG
Installed Ableton Remote Script at:
$(sed 's#^#  #g' "$INSTALLED_LIBRARIES")
Installed export worker and lifecycle launcher under:
  $SUPPORT_DIR

Restart Ableton Live once to load the updated launcher. Future exports will
validate first, ask before replacing global Collections, wait for Live to close,
back up its files, apply the export, and reopen Live.
MSG
