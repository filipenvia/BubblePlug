# Roadmap

BubblePlug is under active development. This roadmap describes the intended
work; items may change as manual Ableton testing reveals issues.

## Before a public release

- [ ] Finish and review the plugin artwork preparation flow. The visual library
  is not considered complete while catalog plugins have no artwork.
- [ ] Complete an end-to-end Ableton Live test: startup, single insert, chain
  building/loading, bubble focus and fullscreen behavior, mixer snapshots, and
  Collections import/export.
- [ ] Verify exported Chain Set `.adg` racks in Live, including supported and
  unsupported chain shapes.
- [ ] Validate installation, upgrade, reinstall and uninstall on a clean macOS
  account, including custom Ableton User Library locations.
- [ ] Run the Universal build on Apple Silicon hardware and publish volunteer
  feedback.
- [ ] Decide the project license before describing the repository as
  open-source.
- [ ] Prepare a screenshot-based setup and usage guide, with personal project
  names and paths removed from screenshots.

## After the first release

- [ ] Add VST2 plugin discovery and loading.
- [ ] Add CLAP plugin discovery and loading.
- [ ] Add AU and Component support, including AUX/Component classification where
  applicable to the host and plug-in format.
- [ ] Improve plugin format classification and plugin-family variant handling
  across supported formats.
- [ ] Show the plug-in preset name in Mixer when the host/plugin makes it
  available; remove the current preset-name display because its values are not
  reliable enough.
- [ ] Investigate a Logic Pro edition or integration, with a clearly defined
  feature scope and macOS compatibility plan.
- [ ] Investigate a Windows edition, including a Windows-native host integration
  and installer. The current app and Ableton Remote Script are macOS-specific.
- [ ] Explore an opt-in community artwork index with exact plugin identity,
  review, copyright and privacy safeguards.
- [ ] Add release automation for building and attaching macOS artifacts and
  checksums to GitHub Releases.
- [ ] Gather compatibility reports across macOS versions, Ableton Live versions
  and Apple Silicon models.

## Not currently planned for the first release

- Plugin validation before loading. Users chose to remove it because it was
  slow and produced false failures.
- VST2, CLAP, Audio Unit and Component support are future roadmap work; the
  initial catalog is VST3-focused.
- Sharing plugin artwork automatically without explicit user consent.
