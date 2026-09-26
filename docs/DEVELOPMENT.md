# Development

## Build the app

```sh
./macos/build-app.sh
```

This compiles the app bundle at `build/PlugSpot.app` using the local macOS SDK
and Swift compiler. On the reference iMac the result is x86_64. The Swift
Package Manager command below currently fails on this machine because its
active Command Line Tools cannot resolve `PlatformPath`; use the app build
script here:

```sh
swift build --package-path macos
```

Universal/arm64 packaging, code signing, notarization, and a user-facing
installer remain release work.

## Install/update the Ableton integration

```sh
./macos/install-launcher.sh
```

This copies `remote_script/PlugSpot` into the default Ableton User Library and
configures the local app launcher. Restart Live to load Python changes. The
Remote Script uses Ableton's internal Control Surface API; the supported
baseline in this project is Live 12.4.2. Compatibility with later patches and
other Live series needs verification.

The installed bridge runs in Live's scheduled callback. Its Unix Domain Socket
worker only queues requests. Mixer snapshots are JSON files outside `.als` at
`~/Library/Application Support/PlugSpot/MixerSnapshots`; app-level snapshot
selection reads these files without needing a live bridge.

## Local library and export

The local SQLite database stores favorites, recent loads, categories, and
plugin labels. **Export JSON Backup** includes favorites, labels, recent records,
and categories; import merges into the existing library. Ableton Collections
import reads Live's local files read-only. Collections export requires explicit
confirmation, asks Live to close, backs up its files, then updates them offline
and reopens Live. This destructive, global export still needs one complete
user-run validation before release.

## Plugin loading and validation

The current load path sends the selected VST3 directly to Live. Plug-in safety
validation was removed at the user's request. The unused validator source/build
artifacts should be cleaned up before release. A plugin can still crash Live
while being instantiated.

## Current verification limits

The user confirmed one manual FabFilter Pro-Q 4 insertion. The app and Python
Remote Script have compiled, but the visual mixer, its change listeners,
snapshot recovery, crash/restart behavior, chain loading across track types,
bubble interaction, and export flow still need real Live checks. No test suite
is currently present in the repository. Real CPU/RAM measurements for the
GitHub report are intentionally deferred until the feature set is complete.
