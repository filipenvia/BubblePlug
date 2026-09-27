#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="${ROOT_DIR}/build/PlugSpot.app"
PKGROOT="${ROOT_DIR}/build/pkgroot"
PKG="${ROOT_DIR}/build/BubblePlug-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SCRIPT_DIR/Resources/Info.plist").pkg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SCRIPT_DIR/Resources/Info.plist")"

"$SCRIPT_DIR/build-app.sh" universal

/bin/rm -rf "$PKGROOT" "$PKG"
/bin/mkdir -p \
  "$PKGROOT/Applications" \
  "$PKGROOT/Library/Application Support/BubblePlug/InstallerPayload/Remote Scripts"
/usr/bin/ditto "$APP" "$PKGROOT/Applications/BubblePlug.app"
/usr/bin/rsync -a --exclude='._*' --exclude='.DS_Store' "$ROOT_DIR/remote_script/PlugSpot/" \
  "$PKGROOT/Library/Application Support/BubblePlug/InstallerPayload/Remote Scripts/PlugSpot/"
/bin/cp "$SCRIPT_DIR/ableton-export-worker.py" \
  "$PKGROOT/Library/Application Support/BubblePlug/InstallerPayload/ableton-export-worker.py"
/bin/cp "$SCRIPT_DIR/configure-launcher.sh" \
  "$PKGROOT/Library/Application Support/BubblePlug/InstallerPayload/configure-launcher.sh"

/usr/bin/find "$PKGROOT/Library/Application Support/BubblePlug/InstallerPayload" \
  -name '._*' -type f -delete
/usr/bin/xattr -cr "$PKGROOT/Library/Application Support/BubblePlug/InstallerPayload" "$SCRIPT_DIR/pkg"

/usr/bin/pkgbuild \
  --root "$PKGROOT" \
  --scripts "$SCRIPT_DIR/pkg" \
  --identifier "com.plugspot.pkg" \
  --version "$VERSION" \
  --install-location / \
  "$PKG"

print "Built installer: $PKG"
print "Package version: $VERSION"
print "Signing and notarization are not configured; this package is for local installation testing."
