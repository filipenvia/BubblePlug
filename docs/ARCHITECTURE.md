# PlugSpot architecture

## Runtime components

```text
PlugSpot SwiftUI app
  ├── plugin library, local SQLite data, settings
  ├── visual mixer and offline recovery-snapshot browser
  └── AbletonLibrary / AbletonBridge
          │ JSON Lines over a user-only Unix Domain Socket
          ▼
Ableton Live Control Surface (Python Remote Script)
  ├── LiveAdapter: Browser, selected track, mixer, artwork scan and device metadata
  ├── BridgeDispatcher: allow-listed methods and protocol validation
  └── BridgeServer: socket worker queue
          │ scheduled callback on Live's Control Surface loop
          ▼
Ableton Live Object Model / Browser API
```

### Swift side

`PlugSpotCore` owns protocol models, the bridge abstraction, SQLite library
store, Ableton Collections reader, VST3 artwork lookup, and first-run artwork
capture coordination. SwiftUI does not
access Live objects directly. `MixerView` reads `get_mixer` on entry, writes an
atomic JSON recovery snapshot, lists snapshots from disk, and can render one
without a Live connection.

### Live side

The Remote Script owns all calls into Live. The socket worker only accepts and
queues JSON Lines; `schedule_message` dispatches requests on Live's control
surface callback. The script listens for track/device/parameter changes and
debounces mixer snapshots. It copies Live-owned values on the callback, then
queues JSON serialization and atomic disk writing on a background worker,
outside the `.als` file. It postpones snapshot collection while Live is playing.
These listeners and crash behavior still need a real Live Set check.

### Local files

- IPC socket: `~/Library/Application Support/PlugSpot/bridge.sock`;
- SQLite library: `~/Library/Application Support/PlugSpot/library.sqlite3`;
- mixer snapshots: `~/Library/Application Support/PlugSpot/MixerSnapshots/*.json`;
- Remote Script log: `~/Documents/plugspot-remote.log`.

The UDS directory is user-only, socket permissions are restricted, and a lock
file prevents competing bridge instances. No network listener is used.

## Lifecycle and window behavior

The Remote Script starts the local launcher when Live loads the PlugSpot
Control Surface. The launcher opens the app when the socket appears and closes
it when a normal Live shutdown removes the socket. During an unexpected Live
crash, the bridge/app may remain waiting for Live to return. The app is an
`LSUIElement` and should not appear in the Dock. The bubble follows Live's
window and is not globally always-on-top. The bubble's window tracking uses a
200 ms timer; its real CPU/Space/full-screen behavior still needs visual
verification.

## Protocol

The implemented v1 methods are `hello`, `ping`, `get_status`, `get_plugins`,
`get_selected_track`, `get_mixer`, `load_plugin`, `refresh_library`, and
`shutdown`. Frames are newline-terminated UTF-8 JSON, capped at 8 MiB. Each
request has a unique ID and a typed, allow-listed method; arbitrary Python or
shell execution is not exposed. See [PROTOCOL.md](PROTOCOL.md).

## Limits

- Browser/load integration uses Ableton's internal Remote Script API and is
  tied to Live versions; 12.4.2 is the tested baseline.
- Only VST3 entries returned by Live's plugin Browser are in the current
  catalog. Variant grouping is provisional.
- A pre-load safety validator is intentionally absent. A plugin can still crash
  Live during instantiation.
- Mixer snapshots contain the mixer/device tree and values that Live exposes;
  they do not promise full recovery of third-party plugin-private state.
- `macos/build-app.sh` can build x86_64, arm64, or Universal bundles. The Intel
  reference Mac can run the x86_64 slice; arm64 has not been runtime-tested on
  Apple Silicon hardware. Volunteer feedback is needed before claiming support.
