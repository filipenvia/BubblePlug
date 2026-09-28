# BubblePlug user guide

BubblePlug is a macOS companion for Ableton Live. It uses Live's PlugSpot
Control Surface script to request plugin insertion and read mixer information.

## Requirements

- macOS 13 or later.
- Ableton Live 12.4.2 is the tested baseline. Compatibility with other versions
  has not been established.
- VST3 plugins indexed by Live.
- The PlugSpot Control Surface installed and selected in Live.

## Install from source

There is no signed, public-ready installer yet. The package built here is for
local testing and is unsigned and not notarized. Building it requires macOS
Command Line Tools or Xcode, Git, CMake, and an internet connection the first
time so the pinned Steinberg VST3 SDK can be downloaded.

1. Download or clone this repository.
2. Open Terminal and change to the repository directory.
3. Build the app and package:

   ```sh
   ./macos/build-pkg.sh
   ```

4. Open the generated `build/BubblePlug-0.1.0.pkg` and follow Installer.
5. In Ableton Live, open **Settings → Link, Tempo & MIDI** and choose
   **PlugSpot** under **Control Surface** if it is not already selected.
6. Restart Live so it loads the Control Surface.

Because the package is unsigned, macOS may show a security warning. Public
release instructions will be updated after the distribution method is finalized.

## First launch and plugin artwork

On first launch, BubblePlug offers to prepare plugin images or open without
them. By default, opening BubblePlug and refreshing the Live catalog do not
launch plugin editors. The first-launch choice is remembered: **Load Missing
Images** enables automatic capture at startup, while **Open Without Loading**
suppresses the prompt. Change this later in **Settings → Plugin Images** or
choose **Load Missing Images** in the main menu to enable it and start now.
**Load All Plugin Images** in Settings starts a one-time scan without changing
the startup choice. The helper opens missing VST3 editors one at a time and
captures their windows. It can take a while, and some plug-ins may not display a
usable editor image. Screen Recording permission is used for this capture flow.
You can assign images manually in **Manage Plugin Images**.

BubblePlug stores its library and images locally. Artwork collection is not
uploaded to a shared service by this build.

## Browse and load plugins

- Search the VST3 catalog and browse All, Favorites, Recent, or Manufacturers.
- Click a plugin once to add it to the chain queue.
- Double-click a plugin to request insertion on the selected Live track.
- Reorder or remove items in the queue, then load the chain.

Live must be open and connected for insertion and mixer operations.

## Chain Sets

Chain Sets can be saved locally, opened, edited, renamed and removed. Supported
chains can be exported as Ableton `.adg` racks. The generated rack formats have
been confirmed working in Live for supported chain types. MIDI-effect racks,
multiple serial instruments and private plugin preset/state are not supported.

## Mixer and recovery snapshots

The Mixer view reads tracks and devices from Live and stores recovery snapshots
outside Live. Snapshots can be opened while Live is unavailable. They are a
recovery aid and do not guarantee restoration of private plug-in state, such as
a Kontakt instrument or library selection.

## Permissions and privacy

Screen Recording is required for plugin editor image capture. BubblePlug does
not use Contacts or Calendar. During image capture, a third-party plugin or its
vendor framework can request access to Calendar, Contacts, Documents, Desktop
or a removable volume. Since the plugin is hosted by BubblePlug's bundled image
helper, macOS may label that request **BubblePlug**. These are not BubblePlug
requirements; only Screen Recording is needed for image capture. You can deny
unexpected requests. Denial may affect a feature of the plugin that requested
access, but not BubblePlug's core library, mixer or Ableton integration. If a
prompt appears, note which plugin was opening so its source can be investigated.

Artwork, favorites, categories, Chain Sets and snapshots remain local in this
development build. Remove personal paths, account names and project details
before posting logs or screenshots to GitHub.

BubblePlug only needs Screen Recording for live plugin-editor image capture.
The first prompt may appear behind Ableton or BubblePlug; check for an existing
System Settings dialog before retrying. If Screen Recording is already enabled
but capture still fails, quit and reopen BubblePlug after changing the setting.

## Troubleshooting

- **BubblePlug does not connect:** confirm Live is running, PlugSpot is selected
  as a Control Surface, and Live has been restarted after installation.
- **No plugins appear:** confirm Live has indexed the VST3 plugins and refresh
  the BubblePlug library.
- **An image is missing or incorrect:** use the image manager to assign or
  replace artwork. The artwork workflow remains under development.
- **A plugin crashes Live:** BubblePlug does not validate plugins before load.
  Restart Live and avoid loading that plugin until its installation is checked.
- **The bubble or fullscreen behavior is wrong:** include macOS version, Live
  version, display arrangement and reproduction steps in a GitHub issue.

## Screenshots

The repository screenshots show BubblePlug connected to a blank Ableton Live
12.4.2 set. They cover the plugin library, Chain Sets view and Live Mixer. They
contain no user project names, plugin paths or unrelated desktop content.
