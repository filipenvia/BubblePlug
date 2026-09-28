# Development

## Build the app

```sh
./macos/build-app.sh
./macos/build-app.sh x86_64
./macos/build-app.sh arm64
```

This compiles the app bundle at `build/BubblePlug.app` using the local macOS SDK
and Swift compiler as a Universal app by default. The `x86_64` and `arm64`
arguments produce architecture-specific app bundles. The Intel reference Mac
can run the x86_64 slice, but the arm64 slice has not been runtime-tested on an
Apple Silicon Mac. The Swift Package Manager command below currently fails on
this machine because its active Command Line Tools cannot resolve
`PlatformPath`; use the app build script here:

```sh
swift build --package-path macos
```

On this development Mac, the build script signs the app and its bundled library
with the persistent local `BubblePlug Local Development` identity in the login
Keychain. Another signing identity can be selected with
`BUBBLEPLUG_SIGNING_IDENTITY`. If neither is available, the script warns and leaves
the app unsigned; macOS may then ask for Screen Recording permission again after
rebuilds. The local certificate is only for development and is not included in
the repository or suitable for distribution. A Developer ID signature,
notarization, and a user-facing installer remain release work. Use the GitHub
Apple Silicon issue template to report volunteer runtime results.

The first clean macOS build also builds the bundled VST3 image helper from a
pinned Steinberg SDK revision. Install CMake for development, or set
`BUBBLEPLUG_CMAKE_BIN` to its executable. Users of the packaged app do not need
CMake or a separate VST host. The helper and its SDK licence are included in
`BubblePlug.app`.

## Install/update the Ableton integration

```sh
./macos/install-launcher.sh
```

This copies `remote_script/BubblePlug` into the default Ableton User Library and
configures the local app launcher. Restart Live to load Python changes. The
Remote Script uses Ableton's internal Control Surface API; the supported
baseline in this project is Live 12.4.2. Compatibility with later patches and
other Live series needs verification.

The installed bridge runs in Live's scheduled callback. Its Unix Domain Socket
worker only queues requests. Mixer snapshots are JSON files outside `.als` at
`~/Library/Application Support/BubblePlug/MixerSnapshots`; app-level snapshot
selection reads these files without needing a live bridge.

## Local library and export

The local SQLite database stores favorites, recent loads, categories, and
plugin labels. **Export JSON Backup** includes favorites, labels, recent records,
and categories; import merges into the existing library. Ableton Collections
import reads Live's local files read-only. Collections export requires explicit
confirmation, asks Live to close, backs up its files, then updates them offline
and reopens Live. An on-disk journal restores the backups if the worker reports
failure. The end-to-end Collections import/export workflow was manually checked
on the reference Mac; see the [release QA record](RELEASE_QA_CHECKLIST.md).

## Plugin loading and validation

The current load path sends the selected VST3 directly to Live. Plug-in safety
validation was removed at the user's request. The validator executable,
validation-target code, cache API, and validator build script have been removed.
An unused validation table in an existing local database is left untouched for
safe migration. A plugin can still crash Live while being instantiated.

## Current verification limits

The reference Mac's manual Ableton workflows were completed on 2026-09-28;
see the [release QA record](RELEASE_QA_CHECKLIST.md). The Python bridge/export
unit suite has eight tests and runs with
`python3 -m unittest discover -s tests -v`. Image capture uses the standalone
VST3 helper rather than a temporary Live track. Controlled capture and resource
measurements are documented in the local QA artifacts, which are excluded from
Git because they may contain machine-specific data. The Universal app's arm64
slice has not been run on Apple Silicon hardware; this is not a release blocker.
