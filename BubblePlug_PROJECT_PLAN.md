# BubblePlug Project Plan

This document records BubblePlug's product requirements, architecture, and
implementation decisions. The public [roadmap](ROADMAP.md) lists future work
only; this document also describes the current design and implemented behavior.

## Product goal

BubblePlug is a lightweight macOS companion for Ableton Live. It helps users
identify and organize installed VST3 plugins visually, then load them onto the
selected Live track. It also provides Chain Sets, a compact Live mixer, and
recovery snapshots stored outside the Live Set.

The product is free, offline-first, and designed to stay out of the way during
music production. It does not process audio or replace Ableton Live.

## Product requirements

### Plugin artwork

Plugin images are central to the library experience. BubblePlug prepares and
stores artwork locally, matches it to exact plugin identities where possible,
and lets users retry captures or assign images manually. Missing or unusable
images can be caused by inactive, damaged, or incomplete local plugins; these
items must remain identifiable and editable.

Image preparation must not run a full scan on every launch. Users can defer it
and start it from the app menu. The capture helper opens one VST3 editor at a
time, captures its window, and exits. Images persist in a local cache and are
decoded on demand with bounded memory use. Artwork is not uploaded by the app.

### Performance

BubblePlug must remain responsive while Live is in use. Avoid recurring full
scans, parallel plugin loading, unbounded image decoding, unnecessary polling,
and resident helper processes. Image preparation may take time, but it must
show progress, support pause and resume, and retain completed work.

### Ableton integration

For the initial release, Live's Browser is the source of truth for plugin
availability. BubblePlug uses the Ableton Remote Script to read the VST3
catalog, selected track, and mixer state, and to request plugin insertion.
Live remains the authority for the resulting Set.

### Local organization and recovery

Favorites, recent items, categories, and Chain Sets are stored locally.
BubblePlug supports up to six categories, matching the available Ableton
Collection colors. Mixer recovery snapshots are saved outside the `.als` file
so they can be inspected if Live closes unexpectedly.

## Main user workflows

1. Start Ableton Live and BubblePlug; the floating bubble follows the Live
   workspace and opens the main app when selected.
2. Browse or search the Live-indexed plugin catalog using artwork, names,
   manufacturers, favorites, and local categories.
3. Add a plugin to the chain with a single click, or load it onto the selected
   Live track with a double-click.
4. Save, edit, reorder, and reload Chain Sets. Export supported chains as
   Ableton `.adg` racks.
5. Open the Mixer to inspect tracks, returns, master, volume, pan, and available
   device information. Save and inspect recovery snapshots outside Live.

## Architecture

```text
BubblePlug macOS app
  ├── SwiftUI interface and local library
  ├── Unix domain socket client
  └── VST3 image capture helper
          │
          ├── Ableton Live Remote Script
          │     └── Live Browser, selected track, mixer, and insertion
          └── Steinberg VST3 interfaces for isolated image capture
```

The IPC uses JSON Lines over a Unix domain socket. Requests and responses are
correlated by ID; the protocol is versioned and documented in
[docs/PROTOCOL.md](docs/PROTOCOL.md). The Remote Script owns Live-specific
operations, while the app owns the interface, local data, and recovery-snapshot
browser. The image helper is separate from Live's audio processing path.

## Platform and compatibility

- Initial platform: macOS.
- Initial plugin format: VST3.
- Tested Ableton baseline: Live 12.4.2.
- The app is built as a Universal binary for Intel and Apple Silicon. The
  maintainers' runtime checks use Intel hardware; Apple Silicon feedback is
  welcome.
- The app and Ableton Remote Script are macOS-specific. Other plugin formats,
  Logic integration, and Windows support are tracked in the roadmap.

## Current implementation

The repository includes the VST3 catalog, search and local organization;
plugin artwork preparation and manual assignment; the floating bubble; plugin
insertion and Chain Sets; `.adg` export for supported chains; Ableton
Collections import/export; the Mixer; and offline recovery snapshots.

Manual workflows have been exercised in Ableton Live, including startup,
plugin insertion, chain editing and loading, bubble and fullscreen behavior,
mixer snapshots, and Collections. The user confirmed `.adg` export for the
supported chain types. See the [release QA checklist](docs/RELEASE_QA_CHECKLIST.md)
for the validation record and the [user guide](docs/USER_GUIDE.md) for setup.

The Mixer displays only preset information provided by the plugin or Live; it
does not invent a preset name. Complete private plugin state, such as a Kontakt
instrument or library selection, is not guaranteed to be present in a recovery
snapshot.

## Distribution principles

The project is distributed through GitHub with installation instructions,
screenshots, a changelog, and a future-work roadmap. The initial macOS package
is unsigned and is not notarized. The app requests macOS permissions only for
features that need them, such as Screen Recording during image capture. Some
permission prompts may be initiated by third-party plugins opened during a
capture; the user guide explains this distinction.

BubblePlug's original code is licensed under MIT. Bundled SDK material and
third-party artwork may have separate terms; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
