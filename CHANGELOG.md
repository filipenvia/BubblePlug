# Changelog

User-facing changes for BubblePlug are listed here. The project is pre-release;
versions and dates may change until the first public release.

## Unreleased

- Improved the GitHub landing page with a build/install quick start, feature
  overview, release status and direct links to the guide, roadmap and changelog.
- Added structured bug-report and feature-request forms with prompts to redact
  private paths, Live Set details and credentials.
- Clarified build prerequisites, unsigned-package limitations and Screen
  Recording permission guidance. Clean product screenshots remain outstanding.
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
- Known limitations: artwork coverage is incomplete and Apple Silicon hardware
  validation is pending.

## 0.1.0 — development build

- Initial project snapshot and working macOS app prototype.
- VST3 catalog, search, favorites, recent plugins, categories and manufacturers.
- Ableton Live Remote Script integration and plugin insertion.
