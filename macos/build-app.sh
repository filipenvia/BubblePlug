#!/bin/zsh
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$PACKAGE_DIR/.." && pwd)"
REQUESTED_ARCH="${1:-universal}"

case "$REQUESTED_ARCH" in
  x86_64|arm64|universal) ;;
  *)
    print -u2 "Usage: $0 [x86_64|arm64|universal]"
    exit 2
    ;;
esac

SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [[ -z "$SDK" || ! -d "$SDK/System/Library/Frameworks/SwiftUI.framework" ]]; then
  SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk"
fi
if [[ ! -d "$SDK/System/Library/Frameworks/SwiftUI.framework" ]]; then
  print -u2 "SwiftUI SDK not found. Install/select Xcode or Command Line Tools."
  exit 1
fi

build_slice() {
  local arch="$1"
  local target="${arch}-apple-macos13.0"
  local output_dir="$ROOT_DIR/build/slices/$arch"
  local modules_dir="$output_dir/swift-modules"
  mkdir -p "$output_dir/Frameworks" "$output_dir/MacOS" "$modules_dir"

  swiftc -sdk "$SDK" -target "$target" -emit-library -emit-module \
    -module-name BubblePlugCore \
    -emit-module-path "$modules_dir/BubblePlugCore.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libBubblePlugCore.dylib \
    "$PACKAGE_DIR/Sources/BubblePlugCore/BridgeProtocol.swift" \
    "$PACKAGE_DIR/Sources/BubblePlugCore/AbletonPluginScanner.swift" \
    "$PACKAGE_DIR/Sources/BubblePlugCore/AbletonLibrary.swift" \
    "$PACKAGE_DIR/Sources/BubblePlugCore/AbletonOrganization.swift" \
    "$PACKAGE_DIR/Sources/BubblePlugCore/LocalLibraryStore.swift" \
    "$PACKAGE_DIR/Sources/BubblePlugCore/UnixDomainSocketClient.swift" \
    -lsqlite3 \
    -o "$output_dir/Frameworks/libBubblePlugCore.dylib"

  swiftc -sdk "$SDK" -target "$target" -parse-as-library \
    -I "$modules_dir" -L "$output_dir/Frameworks" -lBubblePlugCore \
    -framework SwiftUI \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "$PACKAGE_DIR/Sources/BubblePlugApp/BubblePlugApp.swift" \
    "$PACKAGE_DIR/Sources/BubblePlugApp/AbletonChainExporter.swift" \
    "$PACKAGE_DIR/Sources/BubblePlugApp/BrandTheme.swift" \
    "$PACKAGE_DIR/Sources/BubblePlugApp/MixerView.swift" \
    "$PACKAGE_DIR/Sources/BubblePlugApp/PluginArtworkStore.swift" \
    "$PACKAGE_DIR/Sources/BubblePlugApp/BubblePlugSettingsView.swift" \
    -framework Carbon \
    -o "$output_dir/MacOS/BubblePlugApp"
}

if [[ "$REQUESTED_ARCH" == "universal" ]]; then
  build_slice x86_64
  build_slice arm64
  APP="$ROOT_DIR/build/BubblePlug.app"
  APP_ARCHS=(x86_64 arm64)
else
  build_slice "$REQUESTED_ARCH"
  APP="$ROOT_DIR/build/BubblePlug-$REQUESTED_ARCH.app"
  APP_ARCHS=("$REQUESTED_ARCH")
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/MacOS" "$APP/Contents/Resources"
HELPER="$ROOT_DIR/build/vst3-image-helper-build/bin/editorhost.app"
if [[ ! -d "$HELPER" ]]; then
  HELPER="$ROOT_DIR/build/vst3-image-helper-build/bin/Debug/editorhost.app"
fi
if [[ ! -d "$HELPER" ]]; then
  "$PACKAGE_DIR/build-vst3-image-helper.sh"
  HELPER="$ROOT_DIR/build/vst3-image-helper-build/bin/editorhost.app"
  if [[ ! -d "$HELPER" ]]; then
    HELPER="$ROOT_DIR/build/vst3-image-helper-build/bin/Debug/editorhost.app"
  fi
fi
cp "$HELPER/Contents/MacOS/editorhost" "$APP/Contents/MacOS/BubblePlugCapture"
cp "$PACKAGE_DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$PACKAGE_DIR/Sources/BubblePlugApp/Resources/BubblePlug.png" "$APP/Contents/Resources/BubblePlug.png"
cp "$PACKAGE_DIR/Sources/BubblePlugApp/Resources/AudioEffectRackTemplate.adg" "$APP/Contents/Resources/AudioEffectRackTemplate.adg"
cp "$PACKAGE_DIR/Sources/BubblePlugApp/Resources/InstrumentRackTemplate.xml" "$APP/Contents/Resources/InstrumentRackTemplate.xml"
cp "$PACKAGE_DIR/Sources/BubblePlugApp/Resources/ADG_TEMPLATE_NOTICES.txt" "$APP/Contents/Resources/ADG_TEMPLATE_NOTICES.txt"
xattr -cr "$APP/Contents/Resources"
cp "$PACKAGE_DIR/Resources/BubblePlug.icns" "$APP/Contents/Resources/BubblePlug.icns"
cp "$PACKAGE_DIR/Resources/SteinbergVST3SDK-LICENSE.txt" \
  "$APP/Contents/Resources/SteinbergVST3SDK-LICENSE.txt"

if [[ "$REQUESTED_ARCH" == "universal" ]]; then
  lipo -create \
    "$ROOT_DIR/build/slices/x86_64/Frameworks/libBubblePlugCore.dylib" \
    "$ROOT_DIR/build/slices/arm64/Frameworks/libBubblePlugCore.dylib" \
    -output "$APP/Contents/Frameworks/libBubblePlugCore.dylib"
  lipo -create \
    "$ROOT_DIR/build/slices/x86_64/MacOS/BubblePlugApp" \
    "$ROOT_DIR/build/slices/arm64/MacOS/BubblePlugApp" \
    -output "$APP/Contents/MacOS/BubblePlugApp"
else
  local_arch="$REQUESTED_ARCH"
  cp "$ROOT_DIR/build/slices/$local_arch/Frameworks/libBubblePlugCore.dylib" "$APP/Contents/Frameworks/libBubblePlugCore.dylib"
  cp "$ROOT_DIR/build/slices/$local_arch/MacOS/BubblePlugApp" "$APP/Contents/MacOS/BubblePlugApp"
fi

for arch in "${APP_ARCHS[@]}"; do
  lipo "$APP/Contents/MacOS/BubblePlugApp" -verify_arch "$arch"
  lipo "$APP/Contents/Frameworks/libBubblePlugCore.dylib" -verify_arch "$arch"
done

# Use a persistent local signing identity so macOS TCC can recognize this app
# across rebuilds. A Developer ID identity can be supplied for distribution.
SIGNING_IDENTITY="${BUBBLEPLUG_SIGNING_IDENTITY:-BubblePlug Local Development}"
if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$SIGNING_IDENTITY"; then
  codesign --force --sign "$SIGNING_IDENTITY" --identifier com.bubbleplug.app \
    --timestamp=none "$APP/Contents/MacOS/BubblePlugCapture"
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none \
    "$APP/Contents/Frameworks/libBubblePlugCore.dylib"
  codesign --force --sign "$SIGNING_IDENTITY" --identifier com.bubbleplug.app \
    --timestamp=none "$APP"
  codesign --verify --deep --strict "$APP"
else
  print -u2 "Warning: no persistent code-signing identity named '$SIGNING_IDENTITY' is available."
  print -u2 "Set BUBBLEPLUG_SIGNING_IDENTITY to a Developer ID identity or configure local signing."
fi

print "Built $APP"
print "Architectures: $(lipo -archs "$APP/Contents/MacOS/BubblePlugApp")"
