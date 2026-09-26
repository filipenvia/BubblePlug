#!/bin/zsh
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$PACKAGE_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/vst3-validator"
SDK_REVISION="3cdf9ca5d1f5b1b21e0a86832aa4abe55607bd96" # Steinberg VST3 SDK 3.8.1
SDK_DIR="${PLUGSPOT_VST3_SDK_DIR:-$BUILD_DIR/dependencies/vst3sdk}"
MACOS_SDK="${1:-}"

if [[ -z "$MACOS_SDK" || ! -d "$MACOS_SDK/System/Library/Frameworks" ]]; then
  MACOS_SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
fi
if [[ -z "$MACOS_SDK" || ! -d "$MACOS_SDK/System/Library/Frameworks" ]]; then
  MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk"
fi
if [[ ! -d "$MACOS_SDK/System/Library/Frameworks" ]]; then
  print -u2 "macOS SDK not found; install/select Command Line Tools or Xcode."
  exit 1
fi

CMAKE="$(command -v cmake || true)"
if [[ -z "$CMAKE" && -x "$BUILD_DIR/tools/python/bin/cmake" ]]; then
  CMAKE="$BUILD_DIR/tools/python/bin/cmake"
  export PYTHONPATH="$BUILD_DIR/tools/python${PYTHONPATH:+:$PYTHONPATH}"
  export PATH="$BUILD_DIR/tools/python/bin:$PATH"
fi
if [[ -z "$CMAKE" ]]; then
  for PYTHON in python3 python; do
    if command -v "$PYTHON" >/dev/null 2>&1 && "$PYTHON" -m pip --version >/dev/null 2>&1; then
      TOOLS_DIR="$BUILD_DIR/tools"
      mkdir -p "$TOOLS_DIR"
      if "$PYTHON" -m pip install --disable-pip-version-check --quiet --upgrade --target "$TOOLS_DIR/python" cmake; then
        CMAKE_BIN="$(find "$TOOLS_DIR/python" -type f -path '*/bin/cmake' -print -quit)"
        if [[ -n "$CMAKE_BIN" ]]; then
          CMAKE_PARENT="$(dirname "$(dirname "$CMAKE_BIN")")"
          ln -sf "$CMAKE_BIN" "$TOOLS_DIR/cmake"
          ln -sfn "$CMAKE_PARENT/cmake/data" "$TOOLS_DIR/cmake-data"
          CMAKE="$TOOLS_DIR/cmake"
          export PYTHONPATH="$CMAKE_PARENT${PYTHONPATH:+:$PYTHONPATH}"
          export PATH="$CMAKE_PARENT/bin:$PATH"
          break
        fi
      fi
    fi
  done
fi
if [[ -z "$CMAKE" ]]; then
  print -u2 "Could not obtain CMake 3.25+ for the source build. Install CMake or make python3/pip available. Downloaded PlugSpot.app includes the validator."
  exit 1
fi

if [[ ! -f "$SDK_DIR/CMakeLists.txt" ]]; then
  mkdir -p "$(dirname "$SDK_DIR")"
  git clone --filter=blob:none --no-checkout https://github.com/steinbergmedia/vst3sdk.git "$SDK_DIR"
  git -C "$SDK_DIR" checkout --detach "$SDK_REVISION"
  git -C "$SDK_DIR" submodule update --init --depth 1
fi

if [[ -f "$BUILD_DIR/cmake/CMakeCache.txt" ]] && \
  ! rg -q "^CMAKE_HOME_DIRECTORY:INTERNAL=$SDK_DIR$" "$BUILD_DIR/cmake/CMakeCache.txt"; then
  rm -rf "$BUILD_DIR/cmake"
fi

CLANG="$(xcrun --find clang 2>/dev/null || command -v clang)"
CLANGXX="$(xcrun --find clang++ 2>/dev/null || command -v clang++)"
XCODE_VERSION="$( (xcodebuild -version 2>/dev/null || true) | awk '/^Xcode / { print $2; exit }')"
if [[ -z "$XCODE_VERSION" ]]; then
  XCODE_VERSION="$("$CLANG" --version | awk '/Apple clang version/ { split($4, v, "."); print v[1] "." v[2]; exit }')"
fi
export XCODE_VERSION

ARCHITECTURES="${PLUGSPOT_VALIDATOR_ARCHITECTURES:-x86_64;arm64}"
cmake -S "$SDK_DIR" -B "$BUILD_DIR/cmake" \
  -DXCODE_VERSION="$XCODE_VERSION" \
  -DSMTG_ENABLE_VST3_PLUGIN_EXAMPLES=OFF \
  -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF \
  -DSMTG_RUN_VST_VALIDATOR=OFF \
  -DCMAKE_C_COMPILER="$CLANG" \
  -DCMAKE_CXX_COMPILER="$CLANGXX" \
  -DCMAKE_OSX_SYSROOT="$MACOS_SDK" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCHITECTURES" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_BUILD_TYPE=Release

cmake --build "$BUILD_DIR/cmake" --target validator --config Release --parallel "${PLUGSPOT_BUILD_JOBS:-4}"
cp "$BUILD_DIR/cmake/bin/Release/validator" "$BUILD_DIR/PlugSpotVST3Validator"
chmod 755 "$BUILD_DIR/PlugSpotVST3Validator"
mkdir -p "$BUILD_DIR/licenses"
cp "$SDK_DIR/LICENSE.txt" "$BUILD_DIR/licenses/VST3-SDK-LICENSE.txt"
print "$BUILD_DIR/PlugSpotVST3Validator"
