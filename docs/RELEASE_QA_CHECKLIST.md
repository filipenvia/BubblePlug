# Release QA checklist — macOS and Ableton Live

Use this checklist to clear the remaining product validation work. Run it on
the reference Mac with the Ableton version listed in the README. Record the
BubblePlug build, macOS version, Ableton version, result, and a short note for
each case. Do not include personal project names or file paths in public
reports.

Performance measurements are tracked separately and have already been
completed. Ableton `.adg` export for supported Chain Set types is confirmed by
the user and is not a pending test in this checklist.

## Automated checks completed remotely

- **2026-09-28 — Python unit suite:**
  `python3 -m unittest discover -s tests -v` — 8 tests passed. Coverage includes
  local bridge framing and socket round trips, export-document validation,
  plugin-family variant grouping, and the six-category limit. These checks do
  not replace the Ableton Live integration and UI checks below.

## Plugin artwork

- [ ] **IMG-01 — Defer image preparation.** On a clean BubblePlug profile, defer
  artwork preparation at first launch. Confirm the app clearly reports that
  artwork is incomplete, remains usable as intended, offers a way to start the
  full image load later, and does not open plugin editors on its own.
- [ ] **IMG-02 — Start and resume a full image load.** Start the full load and
  interrupt it partway through. Reopen BubblePlug and resume. Confirm completed
  images are retained, only unresolved plugins are retried, and progress/counts
  advance to completion without restarting from zero.
- [ ] **IMG-03 — Check capture quality and matching.** Review representative
  resulting cards against their plugin names and manufacturers. Confirm a
  successful capture shows the intended plugin and is attached to the exact
  plugin entry. Blank/black windows, splash screens, errors and license prompts
  must remain marked unresolved rather than being presented as valid artwork.
  Zero unresolved plugins on this Mac is not required: local plugins may be
  inactive, damaged or incompletely installed.
- [ ] **IMG-04 — Assign and replace artwork.** Manually assign an image to a
  plugin and a manufacturer, restart and rescan, then replace each image.
  Confirm the correct image remains attached to the correct item.
- [ ] **IMG-05 — Permission behavior.** Test Screen Recording permission when
  granted, denied, and already granted. Confirm retry uses the existing grant
  without repeatedly opening the system permission prompt. Confirm BubblePlug's
  own code does not request Contacts or Calendar. If a privacy prompt appears
  while a VST3 editor is opening, record the plugin name and requested access;
  verify denying it does not block BubblePlug's core workflow.
- [ ] **IMG-06 — No repeat scan on ordinary launch.** Complete or defer image
  preparation, interrupt a scan, reopen BubblePlug and refresh the Live catalog.
  Confirm the default startup choice and catalog refresh do not launch plugin
  editors. Choose **Open Without Loading**, restart, and confirm the prompt stays
  dismissed. Then choose **Load Missing Images** and confirm the preference is
  remembered and unresolved images resume on startup. Confirm a manual catalog
  refresh never starts capture. Check that **Load All Plugin Images** in Settings
  runs once without changing the startup preference.

## Startup, bubble, and window behavior

- [ ] **WIN-01 — Live startup and shutdown.** Launch Live and confirm
  BubblePlug connects and starts in bubble mode. Quit Live normally; confirm
  BubblePlug shows a clear disconnected state and offers a working close
  control. Relaunch Live and confirm reconnection without duplicate processes.
- [ ] **WIN-02 — Fullscreen Space.** Put Live in macOS fullscreen, click the
  bubble, and confirm the BubblePlug window appears with visible content in
  Live's fullscreen Space. Repeat after switching to another desktop and back.
- [ ] **WIN-03 — Focus and stacking.** With the full BubblePlug window open,
  click Live and confirm BubblePlug returns to bubble mode. Confirm the bubble
  stays above Live but disappears behind unrelated applications and does not
  steal focus or switch to another Space.
- [ ] **WIN-04 — Move and persist bubble.** Drag the bubble slowly and quickly.
  Confirm it follows the pointer accurately. Test position lock, reset to
  default, and persistence after quitting/reopening Live. Confirm the default
  position is inset from the lower-left edge of Live.
- [ ] **WIN-05 — Window size persistence.** Resize the full BubblePlug window,
  quit Live, reopen it, and confirm the chosen size is restored and fits the
  current display.
- [ ] **WIN-06 — Plugin editor focus after insertion.** Insert a plugin from
  BubblePlug. Confirm the plugin editor and bubble remain reachable without
  requiring an extra click on Live or switching desktops.

## Mixer and recovery snapshots

- [ ] **MIX-01 — Track identity and count.** Open a Live Set with 14 tracks,
  two returns and a master track, with devices on only a subset of tracks.
  Confirm every mixer card has the correct track name and role, empty tracks
  are not replaced by duplicates, and return/master cards appear once.
- [ ] **MIX-02 — Layout with many devices.** Use a track with several plugins
  and a Set with many tracks. Confirm cards remain within their bounds, plugin
  names do not overflow into neighboring cards, and every track can be reached
  by scrolling.
- [ ] **MIX-03 — Values and controls.** Compare displayed volume and pan with
  Live. Change each value through BubblePlug and Live, then confirm both views
  stay synchronized and reopening Mixer refreshes from Live.
- [ ] **MIX-04 — Confirm preset label removal.** The Mixer rendering code no
  longer displays an assumed value such as `Preset · Default`. Confirm the
  result visually in a real Live Set before release.
- [ ] **MIX-05 — Snapshot trigger and recovery.** Open Mixer and confirm it
  refreshes and saves a recovery snapshot. Make a structural/device change and
  save the Live Set; confirm a snapshot is updated. Move a plugin control
  continuously and confirm this does not cause a save on every knob movement.
  Close Live unexpectedly, reopen BubblePlug, and inspect the latest snapshot
  offline.

## Ableton integration and library actions

- [ ] **LIVE-01 — Single-click versus double-click.** Single-click a plugin
  once and confirm it enters the chain queue without loading. Double-click a
  plugin and confirm it loads immediately to the selected compatible track.
- [ ] **LIVE-02 — Build and load a chain.** Add several plugins, change a
  mono/stereo variant where available, reorder and remove items, then load the
  chain. Confirm order, variant and destination track in Live. Repeat on an
  audio track and a MIDI track with compatible devices.
- [ ] **LIVE-03 — Saved Chain Sets.** Save a chain, close/reopen BubblePlug,
  expand the saved set, edit it, and load it. Confirm order and variants persist
  and delete/rename actions affect only the selected set.
- [ ] **LIVE-04 — Collections import.** Import existing Live Collections.
  Confirm names and colors map correctly, categories stay within the six-color
  limit, and importing does not unexpectedly erase BubblePlug favorites or
  categories.
- [ ] **LIVE-05 — Collections export safety and recovery.** Export after
  confirming the warning. Confirm the backup is created, the intended
  Collections are replaced, and the backup can restore the prior state.
  Cancel once and confirm Live's Collections remain untouched.
- [ ] **LIVE-06 — Failure handling.** Try an unavailable or incompatible plugin
  entry. Confirm BubblePlug reports the failed operation, remains responsive,
  and does not send subsequent chain items to the wrong track.

## Confirmed outside this pending checklist

- Ableton `.adg` export works for the supported Chain Set types, confirmed by
  the user.
- Performance measurements for startup, CPU, memory, image capture and extended
  Ableton use have already been completed.
