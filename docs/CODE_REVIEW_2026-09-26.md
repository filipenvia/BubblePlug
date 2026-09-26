# Code review — 2026-09-26

Static review of the app, Swift core, Ableton Remote Script, lifecycle launcher,
export worker, build scripts, and project documentation. The local build was
used as a compiler check; Live behavior was not exercised in this review.

## Fixed during review

- Bubble activation handling treated BubblePlug itself like an unrelated app,
  which could hide the expanded window immediately. It now hides only the bubble
  when BubblePlug activates. Focus changes to an attached settings window are
  ignored by the main-window collapse observer.
- Chain loading previously treated a local SQLite history-write failure as a
  failed Ableton load. Live could have inserted the device while the queue kept
  that item, so retrying could insert it twice. The queue now advances after Live
  accepts the request and reports history errors separately.
- Swift and Python used the same eight-second IPC deadline. If Live stopped
  processing, the client could time out at the same moment as the bridge's
  structured error response. The bridge now responds at seven seconds and the
  client waits ten seconds.

## Remaining findings

### High priority

- **Category model is still limited to six local categories.** The UI, SQLite
  constraint, and JSON exporter all impose Ableton's six color slots. The README
  itself lists reconciling this with unrestricted local categories as unfinished.
  Local categories need independent colors/IDs; export can then map a chosen
  subset to Ableton's six slots with an explicit collision/omission policy.
- **Mixer snapshot serialization and disk sync run on Live's scheduled callback.**
  `plugspot.py` serializes the full mixer/device/parameter tree and calls
  `fsync` from the Live control-surface callback. A large set or plugin with many
  parameters can stall Live's UI/message loop. Copy the Live object data on its
  owning thread, then serialize and write the plain snapshot on a worker.
- **Ableton export spans two files and cannot recover from a process crash
  between them.** Normal exceptions roll the XML config back when the SQLite
  transaction fails, but termination after replacing `Library.cfg` and before
  committing the database can leave mismatched collection names and item colors.
  Add a durable journal/recovery phase, and verify both source files against the
  backup on startup after an interrupted export.

### Medium priority

- **The removed plugin validator remains as dead code.**
  `VST3PluginValidator.swift`, the scanner's validation-target metadata, the
  validation cache methods/table in `LocalLibraryStore`, and the validator build
  script/artifacts are no longer on the app load path. Remove unused source and
  build artifacts before release, while leaving any existing user database table
  untouched for a non-destructive migration.
- **Artwork misses are cached for the entire app session.**
  `PluginArtworkStore` marks a vendor/plugin as requested before extraction; a
  miss cannot retry if Live's scan file or bundle resources become available
  later. Cache successful results only, or add a bounded retry when Live/catalog
  changes.
- **Plugin-family grouping is explicitly provisional.** It uses the last
  whitespace token and a small channel vocabulary, and some genuine product
  names may look like channel suffixes. Validate against the installed catalog
  and make format/variant identity explicit before supporting more formats.
- **One mixer snapshot file is overwritten per saved Set.** This preserves the
  latest recoverable state but not a history of revisions. Confirm that the
  intended retention policy is one latest snapshot per Set; otherwise add bounded
  version history and pruning.
- **Library import is not atomic.** Categories, favorites, recents, and labels
  are applied as separate SQLite writes. A later error can leave a partially
  merged library while the import is reported as failed. Wrap the merge in a
  transaction and roll it back on any error.
- **Importing Ableton Collections silently drops categories past the six-slot
  limit.** The UI skips labels once six local categories exist, but still reports
  the import as successful. Once local categories are decoupled from Live's color
  slots, import every category; until then, report the omitted names/count.
- **Lifecycle and window behavior still need real macOS/Live checks.** In
  particular: Live close/crash, settings sheet focus, switching Spaces/displays,
  and confirming the normal-level bubble appears over Live but is hidden over
  other apps. Static code cannot establish WindowServer ordering behavior.

## Cleanup / consistency

- The codebase has no automated test target or test files. The local app build
  script compiles the shipped sources but does not exercise bridge, export,
  persistence, or window behavior.
- At review time the workspace root had no `.git` directory, so earlier edits
  could not be distinguished from the baseline. A local `main` repository has
  since been initialized and the source snapshot staged; no commit or remote is
  configured yet.
- The local SQLite store still contains a dormant validator table and API; the
  preceding dead-code finding includes these remnants.
- Naming is intentionally mixed while the rename is in progress: visible UI is
  BubblePlug, while bundle ID, executable, SQLite path, launcher, and Remote
  Script remain PlugSpot. Keep this compatibility mapping documented until an
  installer/update migration is ready.
- `setMainWindow(_:)` in `PlugSpotBubbleController` has no call sites; remove it
  once the window registration path is settled.
- Existing docs correctly mark mixer, export, lifecycle, and resource use as
  requiring user-run validation. Do not report those paths as validated based on
  compilation alone.
