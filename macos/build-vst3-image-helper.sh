#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK_DIR="$ROOT_DIR/build/vendor/vst3sdk"
BUILD_DIR="$ROOT_DIR/build/vst3-image-helper-build"
SDK_REVISION="3cdf9ca5d1f5b1b21e0a86832aa4abe55607bd96"
CMAKE_BIN="${BUBBLEPLUG_CMAKE_BIN:-cmake}"

if [[ ! -d "$SDK_DIR/.git" ]]; then
  mkdir -p "$(dirname "$SDK_DIR")"
  git clone --filter=blob:none --recurse-submodules \
    https://github.com/steinbergmedia/vst3sdk.git "$SDK_DIR"
fi
git -C "$SDK_DIR" checkout --detach "$SDK_REVISION"
git -C "$SDK_DIR" submodule update --init --recursive
if git -C "$SDK_DIR/public.sdk" apply --reverse --check "$ROOT_DIR/macos/Tools/editorhost.patch" 2>/dev/null; then
  :
elif git -C "$SDK_DIR/public.sdk" diff --quiet; then
  git -C "$SDK_DIR/public.sdk" apply "$ROOT_DIR/macos/Tools/editorhost.patch"
else
  print -u2 "EditorHost SDK source has unexpected local changes."
  exit 1
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
if ! xcodebuild -version >/dev/null 2>&1; then
  # Steinberg's CMake requires xcodebuild solely to read its version. The
  # Command Line Tools compiler/SDK can build this macOS-only target.
  mkdir -p "$ROOT_DIR/build/helper-toolchain"
  cat > "$ROOT_DIR/build/helper-toolchain/xcodebuild" <<'SHIM'
#!/bin/sh
printf 'Xcode 14.3\nBuild version 14E222b\n'
SHIM
  chmod +x "$ROOT_DIR/build/helper-toolchain/xcodebuild"
  export PATH="$ROOT_DIR/build/helper-toolchain:$PATH"
fi

CC=/usr/bin/clang CXX=/usr/bin/clang++ "$CMAKE_BIN" \
  -S "$SDK_DIR" -B "$BUILD_DIR" \
  -DSMTG_ENABLE_VST3_PLUGIN_EXAMPLES=OFF \
  -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF \
  -DSMTG_ENABLE_VST3_HOSTING_EXAMPLES=ON \
  -DCMAKE_OSX_ARCHITECTURES='x86_64;arm64' \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_OSX_SYSROOT="$SDK"
"$CMAKE_BIN" --build "$BUILD_DIR" --target editorhost -j 4

HELPER="$BUILD_DIR/bin/editorhost.app"
if [[ ! -d "$HELPER" ]]; then
  HELPER="$BUILD_DIR/bin/Debug/editorhost.app"
fi
if [[ ! -d "$HELPER" ]]; then
  print -u2 "The EditorHost build did not produce $HELPER"
  exit 1
fi
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$HELPER/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c 'Set :LSUIElement true' "$HELPER/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.bubbleplug.imagecapture' "$HELPER/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName BubblePlug Image Capture' "$HELPER/Contents/Info.plist"
print "$HELPER"
