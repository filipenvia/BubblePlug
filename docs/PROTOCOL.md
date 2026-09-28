# BubblePlug IPC Protocol — Version 1

The protocol uses JSON Lines. Each request and response is a UTF-8 JSON object
followed by `\n`. A connection can carry multiple requests, each correlated by
`id`. The protocol does not carry executable code.

## Request

```json
{"protocol_version":1,"id":"b4ea8056-...","method":"get_plugins","params":{"offset":0,"limit":100}}
```

Required fields are `protocol_version`, `id`, and `method`. `params` is
optional and depends on the method. The client generates a unique ID for each
request.

## Successful response

```json
{"protocol_version":1,"id":"b4ea8056-...","ok":true,"result":{"items":[{"id":"query:Plugins#VST3:FabFilter:Pro-Q%204","name":"Pro-Q 4","format":"VST3","vendor":"FabFilter"}],"next_offset":100,"total":1373,"truncated":false}}
```

`hello` includes `live_version`, `python_version`, and the capabilities
supported by the Remote Script instance. `python_version` identifies the
Python runtime bundled with Live for diagnostics; app compatibility is based
on the Live version.

## Error response

```json
{"protocol_version":1,"id":"b4ea8056-...","ok":false,"error":{"code":"live_unavailable","message":"Ableton Live is not ready","retryable":true}}
```

The server returns the same `id`. `message` is for diagnostics; clients should
make decisions using `code`, not the message text.

## Version 1 methods

| Method | Parameters | Expected result |
| --- | --- | --- |
| `hello` | none | Protocol, Live and bundled Python versions; bridge capabilities |
| `ping` | none | Short availability response |
| `get_status` | none | Live and BubblePlug surface status |
| `get_plugins` | optional `offset`, `limit` | Paginated list of VST3 plugins recognized by Live's Browser, with `total`, `next_offset` and `truncated` |
| `get_selected_track` | none | Opaque track ID when available and the current track name |
| `get_mixer` | none | Tracks, returns, master and devices/chains, including volume, pan and color when available |
| `load_plugin` | `plugin_id` | Ask Live to load the VST3 item on the selected track; include the effective track |
| `refresh_library` | none | Discard the BubblePlug cache and reread items currently indexed by Live |
| `shutdown` | none | Reserved by the dispatcher; not used by the normal workflow |

`plugin_id` is opaque to the client. The adapter uses the Browser URI. The URI
`query:Plugins#VST3:FabFilter:Pro-Q%204` remained stable after restarting Live.
This was observed for that item and remains an internal adapter detail.

`get_mixer` returns `set_name`, `set_path`, `set_id`, `live_version`,
`tracks`, `return_tracks`, and `master_track`. Each track includes `id`,
`name`, `kind`, `color`, `volume`, `pan`, and `devices`. Devices include
`name`, `class_name`, rack `chains`, automatable parameters exposed by Live,
and `preset_name`/`preset_index` when the plugin provides them. Unsupported
fields are `null` or empty lists. This method only reads state.

Snapshots are written by the Remote Script outside the `.als` file under
`~/Library/Application Support/BubblePlug/MixerSnapshots`. The client reads
these files locally; snapshot queries and writes are not IPC methods.

## Identity and concurrency

- Each request has a client-side deadline and a correlated response.
- Commands that change Live (`load_plugin`) reread the selected track just
  before insertion.
- Image capture loads one plugin at a time, refuses to start during playback,
  and removes its temporary track when finished or paused.
- A load response includes the effective track so the destination is explicit.
- Unknown protocol versions or methods fail without side effects.
- Frame sizes are limited, and `get_plugins` is paginated to avoid unbounded
  responses.

## Initial error codes

`unsupported_protocol`, `unknown_method`, `invalid_request`, `invalid_params`,
`frame_too_large`, `live_unavailable`, `browser_unavailable`,
`plugin_not_found`, `track_unavailable`, `mixer_unavailable`,
`track_not_empty`, `incompatible_track`, `load_failed`, `invalid_plugin`,
`internal_error`.

## Implementation and validation

This contract is implemented by the adapter, Python dispatcher, Remote Script,
and Swift UDS client. Communication and plugin insertion were exercised in
Live 12.4.2; the user confirmed that FabFilter Pro-Q 4 loaded. The user has
also completed the app's manual Ableton workflows, including mixer and
snapshots. Any incompatible protocol change requires incrementing
`protocol_version`.
