# Desktop Companion Windowing v2

Window presentation and gameplay activity have independent state machines.
`FLOATING`, `DOCK_LEFT`, `DOCK_RIGHT`, `COLLAPSED` describe the window.
`ACTIVE`, `PASSIVE` describe gameplay. Mode never writes window geometry.
Legacy invalid activity values recover to Active without resizing.

Float uses a normal decorated, movable, resizable window and releases AppBar
reservation. Dock Left/Right use the existing Windows AppBar sidecar on the
selected monitor edge. Maximized applications respect the reserved work area.
The sidecar watches the game process and removes its AppBar after normal close
or forced termination. X and the ordinary Windows close action remain available.

The inner divider changes dock width while held: left edge for Dock Right,
right edge for Dock Left. Requests coalesce at 50 ms. Desired dock dimensions
are authoritative: late native resize acknowledgements cannot replace a newer
user width. Both processes use physical, per-monitor-DPI coordinates. No game
scene, viewport, session or camera is recreated while resizing.

Inspector controls on DesktopCompanion:

| Setting | Default (physical pixels) |
| --- | ---: |
| min_dock_width | 320 |
| default_dock_width | 480 |
| max_dock_width | 900 |
| collapsed_width | 80 |

Collapse retains activity, session, edge, floating rectangle and dock width.
Expand restores the previous presentation. A collapsed passive opportunity
shows `! FISH`; it remains recoverable through Expand, Active and X.
Ctrl+Shift+F12 toggles activity only.

The keyboard strip is 60 pixels outside the canonical 640×864 game surface.
It uses BOF_Font_Refined at 16, nearest filtering, white text and no outline.
Action names resolve from the live InputMap. Existing literal-key UI bindings
remain explicitly identified rather than pretending they are remappable.

Run the native fixture:

```powershell
& $Godot --path . --rendering-method gl_compatibility --script res://scripts/qa/desktop_companion_docking_qa.gd
& $Python tools/desktop/verify_companion_docking.py --godot $Godot
```

The witness creates its own ordinary maximized window and tests crash cleanup;
it never terminates an unrelated game. Physical divider feel and mixed-monitor
DPI acceptance still deserve designer testing; the fixture checks native width,
attachment, work-area restoration, and unchanged session/camera identities.

## Verification on 2026-10-09

Godot 4.7.2 Windows native Compatibility; disposable QA saves:

| Suite | Result |
| --- | --- |
| desktop_companion_docking_qa | 118/118 |
| Win32 maximized-window/forced-termination/normal-close witness | 3/3 |
| passive_fishing_qa | 47/47 |
| MobileDialogueStateQA rendered | 540/540 |
| MobileOverlayStabilityQA rendered native / Web 390×664 | 538/538 each |
| mobile_portrait_harness_qa | 162/162 |
| mobile_presentation_standard_qa (touch route corrected) | 252/252 |
| dialogue_readability_qa rendered | 125/125 |
| world_interaction_qa | 93/93 |
| session_composition_separation_qa | 102/102 |
| runtime_lifecycle_qa native / mobile | 1832/1832; 1052/1052 |
| fishing_fight_camera_tracking_qa | 164/164 |
| full fishing regression | 22950/22950 |
| Triple Triad backend / dialogue / crafting / Card Maker | 101/101; 175/175; 14/14; 10/10 |
| Fight / presentation / bite timing / stability / fresh-save | 24/24; 10/10; 14/14; 27/27; 55/55 |
| developer_playtest_qa | 90/90 |
| portrait_fishing_acceptance_runner mobile / companion | 47/47; 91/91 |
| mobile_portrait_layout_qa | 44/44 |
| canonical_portrait_surface_qa desktop / rendered mobile | 504/504; 572/572 |
| git diff --check | exit 0 |

Ordinary scripts were invoked with `--script res://scripts/qa/<name>.gd`:
headless for backend/interaction/session/lifecycle/camera/full-fishing/developer;
native `--rendering-method gl_compatibility` for rendering/harness/acceptance.
Lifecycle mobile used `-- --mobile`; companion acceptance `-- --companion`;
canonical mobile `-- --mobile --rendered`; dialogue `-- --rendered`.
The full-fishing runner was `session_contract_runner.gd` and printed
`EXPLICIT FULL FISHING: PASS 22950 / 22950`.

Linux/WSL exported both the isolated Web fixture and production using the existing
Mobile Portrait Web Playtest preset. Browser console reported 538/538, with no
SCRIPT ERROR or ERROR entries. Existing invalid-UID fallback **warnings** in fishing
current-field resources remain out of scope. Native rendered runs also retain the
previous GLES shader-cache-write diagnostics; these are not QA assertion failures.
The existing provisional economy result remains 22/24; no balance values changed.

Published production PCK: 32,226,896 bytes; project.binary: 9,887 bytes, ECFG.
HTTPS PID 18464 was left running. Only the separate loopback QA server was stopped.
The browser's temporary 390×664 override and QA tab were removed.

## Complete changed/new file manifest

Runtime:

- scripts/desktop/desktop_companion.gd
- scripts/desktop/companion_window_platform.gd
- scripts/desktop/companion_keyboard_strip.gd
- scripts/gameplay/passive_fishing_controller.gd (new)
- scripts/gameplay/passive_fishing_controller.gd.uid (new)
- scripts/fishing.gd
- scripts/encounter.gd
- scripts/mobile/mobile_portrait_harness.gd
- tools/desktop/windows_appbar.py

QA:

- scripts/qa/desktop_companion_docking_qa.gd
- tools/desktop/verify_companion_docking.py
- scripts/qa/portrait_fishing_acceptance.gd
- scripts/qa/mobile_presentation_standard_qa.gd
- scripts/qa/passive_fishing_qa.gd (new)
- scripts/qa/passive_fishing_qa.gd.uid (new)
- scripts/qa/mobile_overlay_stability_fixture.gd (new)
- scripts/qa/mobile_overlay_stability_fixture.gd.uid (new)
- actors/mobile/MobileOverlayStabilityQA.tscn (new)

Documentation and generated build:

- docs/platform/desktop_companion_windowing_v2.md (new)
- docs/gameplay/passive_fishing_v1.md (new)
- docs/mobile/mobile_overlay_stability_v1.md (new)
- export/index.html
- export/index.pck

Ignored `build/` contains execution logs, native work-area samples and rendered
captures, not new production infrastructure. No controls mapping, save schema,
camera values, marker/shadow art or economy balance was edited.
