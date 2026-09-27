![BubblePlug](docs/branding/BubblePlug-github-banner.png)

# BubblePlug

BubblePlug is a native macOS companion for Ableton Live. It searches Live's VST3
catalog, organizes plugins locally, and asks Live to load them on the selected
track. The interface is in English; project notes are in Portuguese.

The app uses a midnight-blue theme with cyan accents and subtle iridescent
borders, inspired by its soap-bubble logo. The library, chain builder, mixer,
settings and category editor share the same palette. Branding assets and the
editable SVG are in [docs/branding](docs/branding/README.md).

The technical project name remains **PlugSpot** for existing launcher, Remote
Script, bundle identifier and user-data compatibility.

See the [user guide](docs/USER_GUIDE.md), [changelog](CHANGELOG.md), and
[roadmap](ROADMAP.md). This repository is pre-release; the package currently
available from a local build is for testing and is not signed or notarized.

## Current state

Implemented: VST3 catalog and search, provisional channel-variant grouping,
Favorites, Recent, editable color categories, Manufacturers, Cards/List, partial local plugin
artwork, a temporary chain queue and saved Chain Sets, the floating bubble and its settings, and
Ableton Collections import/export. Mixer view can display a Live Set and save
recovery snapshots outside Live; saved snapshots can be selected and viewed
offline.

The mixer snapshot listener and offline recovery flow have not yet been checked
against a real Live Set. Plugin safety validation was removed at the user's
request; loading a faulty plugin can still crash Live. Complete plugin-internal
state such as a Kontakt library/instrument is not guaranteed to be available in
the snapshot.

Plugin artwork uses exact VST3 snapshots and clearly named local image files.
On first setup, BubblePlug opens missing VST3 editors one at a time in a bundled
image helper, captures its window with BubblePlug's Screen Recording permission,
and caches the thumbnail. This does not add
tracks to Live. Later launches process only missing or new plugins. Images can
also be assigned in **Missing Images**.

Artwork is central to BubblePlug, but local coverage depends on the user's
installed plugins. Inactive, damaged or incompletely installed plugins may not
produce a usable image, so zero missing images on every user's Mac is not a
release requirement. BubblePlug must identify unresolved items, preserve valid
images, allow manual assignment/retry, and avoid repeated full scans during
ordinary use.

## Requirements

- macOS 13 or later;
- Ableton Live 12.4.2 as the tested baseline; later 12.4 patches are accepted
  with a compatibility warning in the app;
- PlugSpot Remote Script installed as a Live Control Surface;
- VST3 plugins indexed by Live.

The build script supports **x86_64**, **arm64**, and **Universal** app bundles.
The default build cross-compiles both architectures into `build/PlugSpot.app`;
single-architecture builds are written to `build/PlugSpot-x86_64.app` or
`build/PlugSpot-arm64.app`. The `arm64` slice can be compiled on the Intel
development Mac, but it has not been run on Apple Silicon hardware. Signing and
notarization for public distribution are still pending; a local `.pkg` can be
built for clean-install testing.

## Local build and Ableton integration setup

```sh
./macos/build-app.sh
./macos/build-app.sh x86_64
./macos/build-app.sh arm64
./macos/build-pkg.sh
./macos/install-launcher.sh
```

The no-argument build produces the Universal app. Use `x86_64` or `arm64` to
build one architecture for diagnosis.

In Live, select **PlugSpot** under **Settings → Link, Tempo & MIDI → Control
Surface** if it is not already selected.

`build-pkg.sh` creates `build/BubblePlug-0.1.0.pkg`. The package installs the
Universal app to `/Applications/BubblePlug.app`, copies the PlugSpot Remote
Script into the logged-in user's default Ableton User Library, and configures
the lifecycle launcher and export worker. Restart Live after installation so
it loads the Control Surface. The package is unsigned for public distribution
and is currently intended for local clean-install testing.

`install-launcher.sh` remains available for development checkouts; it installs
the Remote Script and launcher against `build/PlugSpot.app`.

The app can also be started from `build/PlugSpot.app` after Live has crashed to
inspect existing mixer snapshots. They are stored in
`~/Library/Application Support/PlugSpot/MixerSnapshots`.

## Use

- Single-click a plugin card to add it to the temporary chain queue.
- Double-click to send that plugin to the selected Live track.
- Use the queue controls to reorder/remove entries and load the chain.
- Use the **Mixer** button to view tracks and inspect recovery snapshots.
- Favorites, categories, recent loads, and library backups are local.

## Known gaps before a release

- Complete the pending manual checks for artwork capture, startup, bubble/Spaces,
  Mixer snapshots, plugin/chain loading, and Collections import/export. See the
  [release QA checklist](docs/RELEASE_QA_CHECKLIST.md) for steps and pass
  criteria. Startup, CPU, memory, image-capture timing and extended-use
  measurements have already been completed; image coverage and correctness
  still need review.
- Remove the current preset label from Mixer before the first release; it can
  show a value Live does not reliably identify as the plug-in's actual preset.
- Generalize VST2/VST3/CLAP/AU classification and plugin-family variant
  grouping; the current catalog is VST3-only and grouping is provisional.
- The local category limit is six, matching Ableton's available Collection
  colors. Free-form user tags and removal of obsolete imported labels remain
  open.
- Chain Sets can be saved locally, renamed, removed, and loaded back into the
  chain queue. Clicking a set expands its ordered plugins in place; its chain
  can be edited and saved again. Chain Sets can also be exported as Ableton
  `.adg` racks. Export currently supports serial audio-effect chains and an
  instrument followed by audio effects. MIDI-effect racks, multiple serial
  instruments, and private plugin preset/state are not supported. The user has
  confirmed that `.adg` export works in Live for supported chain types.
- Verify the destructive Ableton Collections export end to end.
- Run the Universal app's arm64 slice on Apple Silicon hardware and collect
  volunteer feedback; choose a project license and finish installer packaging
  and unsigned-distribution instructions. Apple signing and notarization are
  not planned for the initial distribution.

## Apple Silicon testers wanted

BubblePlug can now be built as a Universal app, but the `arm64` build has not
been run on an Apple Silicon Mac. We do not have Apple Silicon hardware for
that check and would appreciate volunteer feedback. If you can try it, please
report your Mac chip, macOS version, Ableton Live version, whether the app
starts and connects, and which plugin loading or mixer flows you exercised.
Please include reproduction steps for failures and remove personal paths or
other private information from logs. Use the
[Apple Silicon feedback issue template](.github/ISSUE_TEMPLATE/apple-silicon-feedback.md).

See [PlugSpot_PROJECT_PLAN.md](PlugSpot_PROJECT_PLAN.md) for the implementation
audit and ordered remaining work. Architecture, development notes, and the
implemented IPC contract are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md), and [docs/PROTOCOL.md](docs/PROTOCOL.md).
