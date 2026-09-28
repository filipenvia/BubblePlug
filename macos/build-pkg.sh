#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="${ROOT_DIR}/build/BubblePlug.app"
PKGROOT="${ROOT_DIR}/build/pkgroot"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SCRIPT_DIR/Resources/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SCRIPT_DIR/Resources/Info.plist")"
PACKAGE_ID="com.bubbleplug.pkg"
COMPONENT_PKG="${ROOT_DIR}/build/BubblePlug-component.pkg"
PKG="${ROOT_DIR}/build/BubblePlug-${VERSION}.pkg"
RESOURCES="${ROOT_DIR}/build/installer-resources"
DISTRIBUTION="${ROOT_DIR}/build/BubblePlug-Distribution.xml"

"$SCRIPT_DIR/build-app.sh" universal
/usr/bin/swift "$SCRIPT_DIR/generate-installer-artwork.swift"

/bin/rm -rf "$PKGROOT" "$COMPONENT_PKG" "$PKG" "$RESOURCES" "$DISTRIBUTION"
/bin/mkdir -p \
  "$PKGROOT/Applications" \
  "$PKGROOT/Library/Application Support/BubblePlug/InstallerPayload/Remote Scripts" \
  "$RESOURCES"
/usr/bin/ditto "$APP" "$PKGROOT/Applications/BubblePlug.app"
/usr/bin/rsync -a --exclude='._*' --exclude='.DS_Store' "$ROOT_DIR/remote_script/BubblePlug/" \
  "$PKGROOT/Library/Application Support/BubblePlug/InstallerPayload/Remote Scripts/BubblePlug/"
/bin/cp "$SCRIPT_DIR/ableton-export-worker.py" \
  "$PKGROOT/Library/Application Support/BubblePlug/InstallerPayload/ableton-export-worker.py"
/bin/cp "$SCRIPT_DIR/configure-launcher.sh" \
  "$PKGROOT/Library/Application Support/BubblePlug/InstallerPayload/configure-launcher.sh"

/usr/bin/find "$PKGROOT/Library/Application Support/BubblePlug/InstallerPayload" \
  -name '._*' -type f -delete
/usr/bin/xattr -cr "$PKGROOT/Library/Application Support/BubblePlug/InstallerPayload" "$SCRIPT_DIR/pkg"

/usr/bin/pkgbuild \
  --root "$PKGROOT" \
  --component-plist "$SCRIPT_DIR/PackageComponents.plist" \
  --scripts "$SCRIPT_DIR/pkg" \
  --identifier "$PACKAGE_ID" \
  --version "$VERSION" \
  --install-location / \
  "$COMPONENT_PKG"

/bin/cp "$SCRIPT_DIR/installer-resources/BubblePlug-Installer.png" \
  "$RESOURCES/BubblePlug-Installer.png"

/bin/cat > "$DISTRIBUTION" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
  <title>BubblePlug</title>
  <background file="BubblePlug-Installer.png" mime-type="image/png" alignment="left" scaling="proportional"/>
  <background-darkAqua file="BubblePlug-Installer.png" mime-type="image/png" alignment="left" scaling="proportional"/>
  <options customize="never" require-scripts="true" rootVolumeOnly="true"/>
  <choices-outline>
    <line choice="default">
      <line choice="$PACKAGE_ID"/>
    </line>
  </choices-outline>
  <choice id="default"/>
  <choice id="$PACKAGE_ID" visible="false">
    <pkg-ref id="$PACKAGE_ID"/>
  </choice>
  <pkg-ref id="$PACKAGE_ID" version="$VERSION" onConclusion="none">BubblePlug-component.pkg</pkg-ref>
</installer-gui-script>
EOF

/usr/bin/productbuild \
  --distribution "$DISTRIBUTION" \
  --resources "$RESOURCES" \
  --package-path "$ROOT_DIR/build" \
  "$PKG"

print "Built installer: $PKG"
print "Package version: $VERSION"
print "Installer artwork: $RESOURCES/BubblePlug-Installer.png"
print "Signing and notarization are not configured; this package is for local installation testing."
