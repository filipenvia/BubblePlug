#!/bin/bash
set -euo pipefail

PURGE_USER_DATA=0
RESTORE_LIVE_COLLECTIONS=0
for arg in "$@"; do
  case "$arg" in
    --purge-user-data) PURGE_USER_DATA=1 ;;
    *)
      echo "Usage: sudo $0 [--purge-user-data]" >&2
      exit 2
      ;;
  esac
done

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  echo "Run this script with sudo so it can remove BubblePlug from /Applications." >&2
  exit 1
fi

USER_NAME="${SUDO_USER:-$(/usr/bin/stat -f '%Su' /dev/console)}"
if [[ -z "$USER_NAME" || "$USER_NAME" == root || "$USER_NAME" == loginwindow ]]; then
  echo "Could not determine the logged-in macOS user." >&2
  exit 1
fi
USER_HOME="$(/usr/bin/dscl . -read "/Users/$USER_NAME" NFSHomeDirectory | /usr/bin/sed 's/^[^:]*: //')"

oldest_collections_backup() {
  local roots=() root
  for root in \
    "$USER_HOME/Library/Application Support/BubblePlug/backups" \
    "$USER_HOME/Library/Application Support/PlugSpot/backups"; do
    [[ -d "$root" ]] && roots+=("$root")
  done
  [[ "${#roots[@]}" -gt 0 ]] || return 0
  /usr/bin/find "${roots[@]}" -mindepth 1 -maxdepth 1 -type d \
    -name 'ableton-collections-*' -print | /usr/bin/sort | /usr/bin/head -n 1
}

if [[ "$#" -eq 0 ]]; then
  echo "Choose what to remove:"
  echo "  1) BubblePlug app and Ableton integration; keep BubblePlug data"
  echo "  2) Remove BubblePlug and erase its local data, images, categories, chains, snapshots and backups"
  echo "  3) Cancel"
  read -r -p 'Choose 1, 2, or 3: ' choice
  case "$choice" in
    1) PURGE_USER_DATA=0 ;;
    2)
      read -r -p 'Type DELETE BUBBLEPLUG DATA to confirm: ' confirmation
      [[ "$confirmation" == "DELETE BUBBLEPLUG DATA" ]] || { echo "Cancelled."; exit 0; }
      PURGE_USER_DATA=1
      backup_dir="$(oldest_collections_backup)"
      if [[ -n "$backup_dir" ]]; then
        echo "A BubblePlug backup of Ableton Live Collections was found."
        echo "Restoring it replaces Live 12.4.2 Collection colors with their state before the first BubblePlug export."
        read -r -p 'Restore that Ableton backup before deleting it? [y/N] ' restore_choice
        [[ "$restore_choice" == y || "$restore_choice" == Y ]] && RESTORE_LIVE_COLLECTIONS=1
      else
        echo "No BubblePlug Ableton Collections backup was found; current Live Collection colors cannot be restored here."
      fi
      ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi
if [[ "$#" -gt 0 && "$PURGE_USER_DATA" -eq 1 ]]; then
  read -r -p 'Type DELETE BUBBLEPLUG DATA to confirm: ' confirmation
  [[ "$confirmation" == "DELETE BUBBLEPLUG DATA" ]] || { echo "Cancelled."; exit 0; }
fi

if /usr/bin/pgrep -x Live >/dev/null 2>&1 || \
   /usr/bin/pgrep -x BubblePlugApp >/dev/null 2>&1 || \
   /usr/bin/pgrep -x PlugSpotApp >/dev/null 2>&1; then
  echo "Quit Ableton Live and BubblePlug before uninstalling." >&2
  exit 1
fi

USER_LIBRARIES=()
add_library() {
  local candidate="$1"
  [[ -n "$candidate" ]] || return 0
  local existing
  for existing in "${USER_LIBRARIES[@]:-}"; do
    [[ "$existing" == "$candidate" ]] && return 0
  done
  USER_LIBRARIES+=("$candidate")
}

while IFS= read -r library; do
  add_library "$library"
done < <(/usr/bin/python3 "$(cd "$(dirname "$0")" && pwd)/ableton-user-libraries.py" "$USER_HOME")

for manifest in \
  "$USER_HOME/Library/Application Support/BubblePlug/installed-user-libraries.txt" \
  "$USER_HOME/Library/Application Support/PlugSpot/installed-user-libraries.txt"; do
  if [[ -f "$manifest" ]]; then
    while IFS= read -r library; do
      add_library "$library"
    done < "$manifest"
  fi
done

echo "This will remove BubblePlug and its Ableton Remote Script from:"
for library in "${USER_LIBRARIES[@]}"; do
  echo "  $library/Remote Scripts/{BubblePlug,PlugSpot}"
done
if [[ "$PURGE_USER_DATA" -eq 1 ]]; then
  echo "It will also permanently delete BubblePlug and legacy PlugSpot local data, including artwork, saved categories/collections, chains, snapshots, caches, logs and settings."
else
  echo "It will preserve the plugin library, artwork, settings, and mixer snapshots."
  read -r -p 'Type REMOVE to continue: ' confirmation
  [[ "$confirmation" == REMOVE ]] || { echo "Cancelled."; exit 0; }
fi

if [[ "$RESTORE_LIVE_COLLECTIONS" -eq 1 ]]; then
  backup_dir="$(oldest_collections_backup)"
  live_db_dir="$USER_HOME/Library/Application Support/Ableton/Live Database"
  live_cfg="$USER_HOME/Library/Preferences/Ableton/Live 12.4.2/Library.cfg"
  if [[ -z "$backup_dir" ]]; then
    echo "The backup disappeared before it could be restored; continuing with uninstall." >&2
  else
    for backup_file in "$backup_dir"/*; do
      [[ -f "$backup_file" ]] || continue
      filename="$(/usr/bin/basename "$backup_file")"
      case "$filename" in
        Library.cfg) target="$live_cfg" ;;
        Live-files-*.db*) target="$live_db_dir/$filename" ;;
        *) continue ;;
      esac
      if [[ -f "$target" ]]; then
        /usr/bin/cp -p "$backup_file" "$target"
      else
        echo "Skipping missing Ableton target: $target" >&2
      fi
    done
    echo "Restored Live 12.4.2 Collection files from $backup_dir."
  fi
fi

for library in "${USER_LIBRARIES[@]}"; do
  /bin/rm -rf \
    "$library/Remote Scripts/BubblePlug" \
    "$library/Remote Scripts/PlugSpot"
  /bin/rmdir "$library/Remote Scripts" 2>/dev/null || true
done

for support in \
  "$USER_HOME/Library/Application Support/BubblePlug" \
  "$USER_HOME/Library/Application Support/PlugSpot"; do
  /bin/rm -f \
    "$support/launch.sh" \
    "$support/ableton-export-worker.py" \
    "$support/launcher.log" \
    "$support/bridge.sock" \
    "$support/bridge.lock" \
    "$support/user-quit.request"
  /bin/rmdir "$support" 2>/dev/null || true
done

# Installer can place the app bundle inside a display-name folder. Remove only
# the known app bundle paths, then remove those wrapper directories if empty.
for app_path in \
  /Applications/BubblePlug.app \
  /Applications/PlugSpot.app \
  /Applications/BubblePlug/BubblePlug.app \
  /Applications/BubblePlug.localized/BubblePlug.app \
  /Applications/PlugSpot/PlugSpot.app \
  /Applications/PlugSpot.localized/PlugSpot.app; do
  /bin/rm -rf "$app_path"
done
/bin/rm -f \
  "/Applications/BubblePlug/Uninstall BubblePlug.command" \
  "/Applications/BubblePlug.localized/Uninstall BubblePlug.command" \
  "/Applications/PlugSpot/Uninstall PlugSpot.command" \
  "/Applications/PlugSpot.localized/Uninstall PlugSpot.command"
for wrapper in \
  /Applications/BubblePlug/.localized \
  /Applications/BubblePlug.localized/.localized \
  /Applications/BubblePlug \
  /Applications/BubblePlug.localized \
  /Applications/PlugSpot/.localized \
  /Applications/PlugSpot.localized/.localized \
  /Applications/PlugSpot \
  /Applications/PlugSpot.localized; do
  /bin/rmdir "$wrapper" 2>/dev/null || true
done
/bin/rm -rf "/Library/Application Support/BubblePlug"

for package_id in com.bubbleplug.pkg com.plugspot.pkg; do
  if /usr/sbin/pkgutil --pkg-info "$package_id" >/dev/null 2>&1; then
    /usr/sbin/pkgutil --forget "$package_id" >/dev/null
  fi
done

if [[ "$PURGE_USER_DATA" -eq 1 ]]; then
  /bin/rm -rf \
    "$USER_HOME/Library/Application Support/BubblePlug" \
    "$USER_HOME/Library/Application Support/PlugSpot" \
    "$USER_HOME/Library/Caches/BubblePlug" \
    "$USER_HOME/Library/Caches/PlugSpot" \
    "$USER_HOME/Library/Caches/com.bubbleplug.app" \
    "$USER_HOME/Library/Caches/com.bubbleplug.imagecapture" \
    "$USER_HOME/Library/Caches/com.plugspot.app" \
    "$USER_HOME/Library/Caches/com.plugspot.imagecapture" \
    "$USER_HOME/Library/WebKit/com.bubbleplug.app" \
    "$USER_HOME/Library/WebKit/com.bubbleplug.imagecapture" \
    "$USER_HOME/Library/WebKit/com.plugspot.app" \
    "$USER_HOME/Library/WebKit/com.plugspot.imagecapture" \
    "$USER_HOME/Library/HTTPStorages/com.bubbleplug.app" \
    "$USER_HOME/Library/HTTPStorages/com.bubbleplug.app.binarycookies" \
    "$USER_HOME/Library/HTTPStorages/com.bubbleplug.imagecapture" \
    "$USER_HOME/Library/HTTPStorages/com.bubbleplug.imagecapture.binarycookies" \
    "$USER_HOME/Library/HTTPStorages/com.plugspot.app" \
    "$USER_HOME/Library/HTTPStorages/com.plugspot.app.binarycookies" \
    "$USER_HOME/Library/HTTPStorages/com.plugspot.imagecapture" \
    "$USER_HOME/Library/HTTPStorages/com.plugspot.imagecapture.binarycookies" \
    "$USER_HOME/Library/Saved Application State/com.bubbleplug.app.savedState" \
    "$USER_HOME/Library/Saved Application State/com.bubbleplug.imagecapture.savedState" \
    "$USER_HOME/Library/Saved Application State/com.plugspot.app.savedState" \
    "$USER_HOME/Library/Saved Application State/com.plugspot.imagecapture.savedState"
  /bin/rm -f \
    "$USER_HOME/Library/Preferences/com.bubbleplug.app.plist" \
    "$USER_HOME/Library/Preferences/com.bubbleplug.imagecapture.plist" \
    "$USER_HOME/Library/Preferences/com.plugspot.app.plist" \
    "$USER_HOME/Library/Preferences/com.plugspot.imagecapture.plist"
  for reports in \
    "$USER_HOME/Library/Logs/DiagnosticReports" \
    "$USER_HOME/Library/Logs/DiagnosticReports/Retired"; do
    if [[ -d "$reports" ]]; then
      /usr/bin/find "$reports" -maxdepth 1 -type f \
        \( -name 'BubblePlugApp-*.ips' -o -name 'BubblePlugCapture-*.ips' \
        -o -name 'PlugSpotApp-*.ips' -o -name 'PlugSpotVST3Validator-*.ips' \) \
        -delete
    fi
  done
  /usr/bin/sudo -u "$USER_NAME" /usr/bin/tccutil reset All com.bubbleplug.app >/dev/null 2>&1 || true
  /usr/bin/sudo -u "$USER_NAME" /usr/bin/tccutil reset All com.bubbleplug.imagecapture >/dev/null 2>&1 || true
  /usr/bin/sudo -u "$USER_NAME" /usr/bin/tccutil reset All com.plugspot.app >/dev/null 2>&1 || true
  /usr/bin/sudo -u "$USER_NAME" /usr/bin/tccutil reset All com.plugspot.imagecapture >/dev/null 2>&1 || true
fi

echo "BubblePlug and its Ableton integration have been removed."
if [[ "$PURGE_USER_DATA" -eq 0 ]]; then
  echo "User data was preserved. Reinstalling can reuse the existing library and artwork."
else
  echo "BubblePlug local data and its macOS privacy permission records were removed."
  echo "Ableton Live's own Collections and database were left untouched."
fi
