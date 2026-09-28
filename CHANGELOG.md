# Changelog

User-facing changes for BubblePlug are listed here. The project is pre-release;
versions and dates may change until the first public release.

## Unreleased

- Improved the GitHub landing page with a build/install quick start, feature
  overview, release status and direct links to the guide, roadmap and changelog.
- Expanded the user guide into an illustrated setup and usage walkthrough with
  clean screenshots, first-launch image choices, privacy notes and troubleshooting.
- Added an MIT license for BubblePlug's original code and a separate notice for
  the bundled Steinberg SDK and third-party plugin artwork.
- Fixed macOS Installer relocating BubblePlug into a development build folder
  during a clean reinstall by marking the packaged app bundle non-relocatable.
- Added structured bug-report and feature-request forms with prompts to redact
  private paths, Live Set details and credentials.
- Clarified build prerequisites, unsigned-package limitations and Screen
  Recording permission guidance. Manual Ableton integration and UI checks are
  recorded complete in the release QA checklist.
- Removed the unverified preset name from Mixer and visually confirmed the
  result in Ableton Live.
- Made the first-launch image choice persistent: **Load Missing Images** enables
  automatic startup capture, while **Open Without Loading** suppresses the
  prompt. The main menu can change to automatic loading and start it immediately;
  **Capture Missing Images Once** in Settings does not change the preference and
  only searches/captures unresolved plugins. Catalog refresh never starts image
  capture. Ambiguous legacy one-time-scan preferences are
  reset to ask once instead of triggering an unexpected scan after updating.
- Added a Universal macOS build path for Intel and Apple Silicon.
- Added persistent Chain Sets and Ableton `.adg` rack export for supported
  serial chains.
- Added local mixer recovery snapshots and offline snapshot browsing.
- Added first-run plugin artwork preparation through a bundled VST3 helper.
- Shared artwork-capture state between the startup scene and expanded window to
  prevent duplicate first-run scans.
- Documented that privacy prompts observed during plugin capture may come from
  hosted third-party plugins; BubblePlug itself does not request Contacts or
  Calendar access.
- Updated the interface with the BubblePlug visual identity.
- Removed external plug-in validation from the load flow.
- Known limitations: local artwork coverage can be incomplete, and the arm64
  build has not been run on Apple Silicon hardware. Neither blocks the initial
  release.

## 0.1.0 — development build

- Initial project snapshot and working macOS app prototype.
- VST3 catalog, search, favorites, recent plugins, categories and manufacturers.
- Ableton Live Remote Script integration and plugin insertion.
