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

## Findings addressed after the initial review

- **Six categories are an accepted V1 limit.** The user confirmed that local
  categories should share Ableton's six color slots; README and project plan now
  state this as a decision rather than an open issue.
- **Mixer file work moved off Live's callback.** The callback now copies the
  mixer data and queues plain values; a background worker encodes and writes
  them. Live API reads still happen on Live's own callback and need manual
  performance validation.
- **Collections export now has a durable recovery journal.** The worker records
  backup paths before changing either Ableton file; the launcher restores those
  files if export fails, and the next export attempt recovers any journal left
  behind. Live validation remains required.
- **PlugSpot library imports now use one SQLite transaction.** Any failure
  rolls back categories, favorites, recents and labels together.
- **Dead plugin validation code was removed.** Existing local databases are not
  destructively migrated; any old validation table remains unused.

## Remaining findings

### High priority

- **Lifecycle and window behavior still need real macOS/Live checks.** In
  particular: Live close/crash, settings sheet focus, switching Spaces/displays,
  and confirming the normal-level bubble appears over Live but is hidden over
  other apps. Static code cannot establish WindowServer ordering behavior.
- **Collections import can omit categories beyond the six-slot limit.** The UI
  should report omitted names/count instead of silently claiming a complete
  import.

### Medium priority

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

## Cleanup / consistency

- The codebase has no automated test target or test files. The local app build
  script compiles the shipped sources but does not exercise bridge, export,
  persistence, or window behavior.
- The project has a clean local `main` commit; no GitHub remote is configured.
- Existing local SQLite databases may still contain the unused plugin validation
  table. It is retained for non-destructive compatibility and is no longer read.
- Naming is intentionally mixed while the rename is in progress: visible UI is
  BubblePlug, while bundle ID, executable, SQLite path, launcher, and Remote
  Script remain PlugSpot. Keep this compatibility mapping documented until an
  installer/update migration is ready.
- The unused `setMainWindow(_:)` helper was removed during the follow-up cleanup.
- Existing docs correctly mark mixer, export, lifecycle, and resource use as
  requiring user-run validation. Do not report those paths as validated based on
  compilation alone.
