# BubblePlug identity

Approved direction: a mirrored B made from two cropped rotary knobs (smaller
above, larger below), joined to a fader, inside an iridescent soap bubble.

## Assets

- `../../macos/Sources/PlugSpotApp/Resources/BubblePlug.png`: approved generated
  raster artwork used by the app header and floating bubble.
- `../../macos/Resources/BubblePlug.icns`: macOS application icon, exported from
  the approved artwork at standard icon sizes.
- `BubblePlug-logo.svg`: editable vector recreation with gradients and shadows;
  contains real paths, not an embedded bitmap. The soap-film texture is simplified
  compared with the approved raster.
- `BubblePlug-logo-vector-preview.png`: 1024 × 1024 preview of the SVG.
- `BubblePlug-github-banner.svg`: editable 1600 × 560 GitHub README banner.
- `BubblePlug-github-banner.png`: raster banner used by the root README.

Older images in this folder are historical proposals, not the current identity.

## Interface

`BrandTheme.swift` defines the shared palette and caches the logo. Navy surfaces,
white text and cyan actions keep the content readable; pink/violet reflections
are restrained border accents. Category and Ableton track colors retain their
functional meaning. No animated reflections or extra polling are introduced.

Public window/header branding is BubblePlug. Existing PlugSpot bundle ID,
executable, launcher paths, Remote Script and storage keys remain compatible.

## Export

`export-assets.cjs` exports SVG previews and the macOS icon set using Node.js,
Sharp and macOS `iconutil`. These are development tools, not app dependencies.
Run it with Sharp available through `NODE_PATH`, then run `macos/build-app.sh`.

The native app was compiled after the visual changes. Interactive review in
Ableton, multi-display behavior and small-size legibility remain for the user's
manual review.
