# Sprint 0 — Technical Feasibility Record

Historical record of the technical feasibility work performed on 2026-09-25
on the test Mac. The gate and checked boxes below reflect the state at the end
of that sprint. The current project state and remaining work are documented in
`BubblePlug_PROJECT_PLAN.md`. Internal API IDs, properties, and methods must
not be assumed stable.

## Environment

- Date: 2026-09-25
- macOS version: macOS 13.7.8 (Ventura)
- Model and architecture: iMac18,2, Intel Core i7 quad-core 3.6 GHz, 20 GB RAM, x86_64
- Ableton Live version: Live 12 Suite 12.4.2
- Remote Script Python version, if known: Python 3.11.6 (embedded)
- Test VST3 plugins: 418 bundles found in `/Library/Audio/Plug-Ins/VST3`; 1,373 loadable items recognized in the VST3 Browser tree.

## Observations

| Check | Result | Evidence / notes |
| --- | --- | --- |
| Remote Script loads | Confirmed | `BubblePlug` appears in Live's MIDI Remote Scripts section of `Log.txt` and writes to the diagnostic log. |
| Live version detected | Confirmed | 12.4.2 via `Application.get_major_version/minor_version/bugfix_version`. |
| Selected track detected | Confirmed | The selected test track was `1-MIDI`. |
| Browser can be enumerated | Confirmed | The `Plug-Ins` tree was traversed: 2,223 items without truncation. URIs distinguish `#VST3:` from `#VST:`. |
| VST3 items distinguished from other items | Confirmed | For example, the Pro-Q 4 VST3 URI is `query:Plugins#VST3:FabFilter:Pro-Q%204`; a VST item with the same name also exists under `#VST:Local`. |
| ID remains the same after restarting Live | Confirmed for the observed URI | `query:Plugins#VST3:FabFilter:Pro-Q%204` was identical before and after restarting Live. |
| VST3 insertion request reaches Live | Confirmed | A real request over the UDS socket used `query:Plugins#VST3:Arturia:Pigments`; the response was `ok:true`, with effective track `1-Pigments`. `Log.txt` recorded “Going to create: Pigments”. |
| Pigments processor initializes | Failed | Live logged `plugin processor could not be initialized` and `Failed: Pigments` for Arturia Pigments 4.0.1.2949. The insertion API was reached; it was not determined whether the failure was specific to this plugin. |
| FabFilter Pro-Q 4 VST3 loads through the app | Confirmed by the user | The user selected an audio track and confirmed that loading from the BubblePlug interface worked. |
| VST2/AU formats or Live devices appear in the VST3 list | No | The adapter starts from `application.browser.plugins` and accepts only URIs with the literal prefix `query:Plugins#VST3:`. The Browser separated `#VST:` and `#VST3:`; Live devices appear under other nodes (`instruments`, `audio_effects`, etc.). |
| Channel variants appear as separate plugins | Confirmed | The snapshot had 1,373 entries after removing 279 `.vstpreset` items. 720 entries were Waves and included `Mono`, `Stereo`, `Mono/Stereo`, and surround variants. Grouping channel suffixes produced about 982 plugin names, including 331 Waves names. |
| Second load on a different target | Not run | The selected track had become `1-Pigments`; the adapter rejected a second load because that track was no longer empty (`track_not_empty`). The safety check was not bypassed on the same track. |
| Three consecutive loads work | Pending at the time of this sprint | |
| Insertion observed on audio/MIDI/return/master tracks | Pending at the time of this sprint | |

## Recorded setup and findings

- Test Mac: macOS 13.7.8 (Ventura), iMac18,2, Intel x86_64, 20 GB RAM.
- Live 12 Suite 12.4.2 ran the BubblePlug script from
  `~/Music/Ableton/User Library/Remote Scripts/BubblePlug`.
- Live embeds Python 3.11.6. The API used by this script exposes `application`
  and `song` as `ControlSurface` properties.
- `Application.browser` exists and exposes `plugins`, `instruments`,
  `audio_effects`, `midi_effects`, `sounds`, `drums`, `max_for_live`,
  `user_folders`, and `user_library`.
- Direct child counts observed: Plug-Ins 2, Instruments 24, Audio Effects 47,
  MIDI Effects 16, Sounds 17, Drums 167, Max for Live 3, User Library 24.
- The Plug-Ins tree traversal returned 2,223 items without truncation. Live's
  Browser recognized 1,373 loadable entries under `#VST3:`. The FabFilter
  Pro-Q 4 URI was the same after restarting Live:
  `query:Plugins#VST3:FabFilter:Pro-Q%204`. This confirms only the observed
  case, not all IDs or variants.
- Physical VST3 bundle counts differed across measurements in this sprint
  (418/419 system bundles, plus one in the user folder). Browser-indexed items
  are identified by URI. The Pro-Q URI persisted, but general identity
  persistence remains unconfirmed.
- The physical count observed in `/Library/Audio/Plug-Ins/VST3` was 419 system
  bundles, with one more in `~/Library/Audio/Plug-Ins/VST3`. Separate folders
  also contained 244 VST2 bundles and 385 AU components; none of these formats
  is admitted by the catalog URI prefix.
- The difference between physical bundles and Live items is mainly due to
  Waveshell expansion into mono, stereo, and surround variants. BubblePlug now
  groups these options into families and retains exact URIs in the variant
  selector. The 1,373/982 figures come from the Live snapshot and name
  normalization, not from the number of installed files.
- The presence of VST3 bundles on disk does not prove that Live indexed or
  recognized them. The Browser tree distinguishes `#VST3:` from `#VST:` and
  contains the Pro-Q 4 VST3 item.
- The first insertion test selected the wrong item by name
  (`query:Plugins#VST:Local:FabFilter%20Pro-Q%204`) while a MIDI track was
  active. Immediately after the log entry preceding `browser.load_item`, Live
  12.4.2 suffered `EXC_BAD_ACCESS` on the main thread (report
  `Live-2026-09-25-152844.ips`). The exact cause was not symbolicated; the
  automatic call and one-shot trigger were removed. Live then started again
  and traversed the tree without error, recognizing 1,373 VST3 items.
- The first test also encountered an error accessing `application`; this was
  fixed in the script and validated after restarting Live and selecting
  BubblePlug.
- After the crash, Live reopened with the safe script. A new enumeration
  completed without error: 2,223 items traversed, 1,373 VST3 entries classified,
  and the Pro-Q 4 URI repeated.

## Gate decision

- [ ] Proceed to minimal IPC
- [x] Investigate API and compatibility
- [ ] Reassess feasibility

Rationale: The first attempt (VST URI, at startup, on a MIDI track) coincided
with a native crash. A controlled test proved that the UDS → Live callback →
`browser.load_item` path works. Although Pigments failed to initialize, the
user confirmed that FabFilter Pro-Q 4 VST3 loaded through the app on an audio
track. Plugin insertion is feasible; multiple loads and other track types were
still pending at the end of this historical sprint.
