#!/bin/zsh
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$PACKAGE_DIR/.." && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [[ -z "$SDK" || ! -d "$SDK/System/Library/Frameworks/SwiftUI.framework" ]]; then
  SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk"
fi
if [[ ! -d "$SDK/System/Library/Frameworks/SwiftUI.framework" ]]; then
  print -u2 "SwiftUI SDK not found. Install/select Xcode or Command Line Tools."
  exit 1
fi

APP="$ROOT_DIR/build/PlugSpot.app"
FRAMEWORKS="$APP/Contents/Frameworks"
MODULES="$ROOT_DIR/build/swift-modules"
mkdir -p "$FRAMEWORKS" "$APP/Contents/MacOS" "$MODULES"
cp "$PACKAGE_DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp "$PACKAGE_DIR/Sources/PlugSpotApp/Resources/BubblePlug.png" "$APP/Contents/Resources/BubblePlug.png"
cp "$PACKAGE_DIR/Resources/BubblePlug.icns" "$APP/Contents/Resources/BubblePlug.icns"

rm -rf "$APP/Contents/Helpers/PlugSpotVST3Validator"
rm -f "$APP/Contents/Resources/ThirdPartyLicenses/VST3-SDK-LICENSE.txt"

swiftc -sdk "$SDK" -emit-library -emit-module \
  -module-name PlugSpotCore \
  -emit-module-path "$MODULES/PlugSpotCore.swiftmodule" \
  -Xlinker -install_name -Xlinker @rpath/libPlugSpotCore.dylib \
  "$PACKAGE_DIR/Sources/PlugSpotCore/BridgeProtocol.swift" \
  "$PACKAGE_DIR/Sources/PlugSpotCore/AbletonPluginScanner.swift" \
  "$PACKAGE_DIR/Sources/PlugSpotCore/AbletonLibrary.swift" \
  "$PACKAGE_DIR/Sources/PlugSpotCore/AbletonOrganization.swift" \
  "$PACKAGE_DIR/Sources/PlugSpotCore/LocalLibraryStore.swift" \
  "$PACKAGE_DIR/Sources/PlugSpotCore/UnixDomainSocketClient.swift" \
  -lsqlite3 \
  -o "$FRAMEWORKS/libPlugSpotCore.dylib"

swiftc -sdk "$SDK" -parse-as-library \
  -I "$MODULES" -L "$FRAMEWORKS" -lPlugSpotCore \
  -framework SwiftUI \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "$PACKAGE_DIR/Sources/PlugSpotApp/PlugSpotApp.swift" \
  "$PACKAGE_DIR/Sources/PlugSpotApp/BrandTheme.swift" \
  "$PACKAGE_DIR/Sources/PlugSpotApp/MixerView.swift" \
  "$PACKAGE_DIR/Sources/PlugSpotApp/PluginArtworkStore.swift" \
  "$PACKAGE_DIR/Sources/PlugSpotApp/PlugSpotSettingsView.swift" \
  -framework Carbon \
  -o "$APP/Contents/MacOS/PlugSpotApp"

print "Built $APP"
