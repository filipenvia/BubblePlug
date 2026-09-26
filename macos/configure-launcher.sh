#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT_DIR="$HOME/Library/Application Support/PlugSpot"
mkdir -p "$SUPPORT_DIR"
cp "$ROOT_DIR/macos/ableton-export-worker.py" "$SUPPORT_DIR/ableton-export-worker.py"
chmod 700 "$SUPPORT_DIR/ableton-export-worker.py"
cat > "$SUPPORT_DIR/launch.sh" <<EOF_LAUNCHER
#!/bin/sh
set -u
APP="$ROOT_DIR/build/PlugSpot.app"
SOCKET="\$HOME/Library/Application Support/PlugSpot/bridge.sock"
PENDING="\$HOME/Library/Application Support/PlugSpot/pending-ableton-export.json"
RESULT="\$HOME/Library/Application Support/PlugSpot/ableton-export-result.json"
WORKER="\$HOME/Library/Application Support/PlugSpot/ableton-export-worker.py"
QUIT_REQUEST="\$HOME/Library/Application Support/PlugSpot/user-quit.request"
LOG="\$HOME/Library/Application Support/PlugSpot/launcher.log"
WAIT=0
RESTARTS=0
RESTART_LIMIT_REACHED=0
LAST_LAUNCH=0

for i in 1 2 3 4 5 6 7 8 9 10; do
  [ -S "\$SOCKET" ] && break
  sleep 1
done
[ -S "\$SOCKET" ] || exit 0
rm -f "\$QUIT_REQUEST"
open -a "\$APP" || exit 0
LAST_LAUNCH=\$(date +%s)

while [ -S "\$SOCKET" ]; do
  sleep 1
  WAIT=\$((WAIT + 1))
  if [ ! -f "\$QUIT_REQUEST" ] && [ "\$RESTART_LIMIT_REACHED" -eq 0 ] && ! pgrep -x PlugSpotApp >/dev/null 2>&1; then
    NOW=\$(date +%s)
    # Allow a just-launched instance time to finish starting before treating
    # the missing process as a crash.
    if [ \$((NOW - LAST_LAUNCH)) -ge 10 ]; then
      RESTARTS=\$((RESTARTS + 1))
      if [ "\$RESTARTS" -le 3 ]; then
        printf '%s PlugSpot was not running; restart attempt %s/3\n' "\$(date '+%Y-%m-%d %H:%M:%S')" "\$RESTARTS" >> "\$LOG"
        open -a "\$APP" || true
        LAST_LAUNCH=\$(date +%s)
      else
        RESTART_LIMIT_REACHED=1
        printf '%s PlugSpot restart limit reached for this Live session\n' "\$(date '+%Y-%m-%d %H:%M:%S')" >> "\$LOG"
        osascript -e 'display notification "PlugSpot could not stay open. Reopen it manually; the library is saved." with title "PlugSpot"' >/dev/null 2>&1 || true
      fi
    fi
  fi
  if [ -f "\$PENDING" ] && [ "\$WAIT" -ge 600 ]; then
    rm -f "\$PENDING"
    printf '%s\n' '{"ok":false,"error":"Ableton stayed open; the export was cancelled without changing its files."}' > "\$RESULT"
    osascript -e 'display notification "Export cancelled. Ableton did not close; no files were changed." with title "PlugSpot"' >/dev/null 2>&1 || true
  fi
done

osascript -e 'tell application id "com.plugspot.app" to quit' >/dev/null 2>&1 || true
if [ -f "\$PENDING" ]; then
  CLOSED=0
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
    if ! pgrep -x Live >/dev/null 2>&1; then CLOSED=1; break; fi
    sleep 1
  done
  if [ "\$CLOSED" -eq 1 ]; then
    /usr/bin/python3 "\$WORKER" --apply "\$PENDING" "\$RESULT" >> "\$LOG" 2>&1
    APPLY_STATUS=\$?
  else
    printf '%s\n' '{"ok":false,"error":"Ableton did not fully close. No files were changed."}' > "\$RESULT"
    APPLY_STATUS=1
  fi
  rm -f "\$PENDING"
  if [ "\$APPLY_STATUS" -ne 0 ]; then
    osascript -e 'display notification "Export stopped safely. Open PlugSpot after Live restarts for details." with title "PlugSpot"' >/dev/null 2>&1 || true
  fi
  open -b com.ableton.live >/dev/null 2>&1 || true
  exit 0
fi
EOF_LAUNCHER
chmod 700 "$SUPPORT_DIR/launch.sh"
print "Configured Ableton lifecycle launcher at $SUPPORT_DIR/launch.sh"
