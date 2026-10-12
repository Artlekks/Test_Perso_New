# Desktop Companion v2

2026-10-11. Builds on the uncommitted v1 changes without replacing them. No fishing camera/controller, physics, HUD, mobile layout, save or economy files changed.

## Native root cause and classification

`windows_appbar.py:AppBar.apply()` negotiated and reserved a full-height side rectangle with ABM_QUERYPOS/ABM_SETPOS, then used `min(command.height, reservation_height)` and centered a shorter window inside it. Godot requested a height derived from 4:3 content. At minimum width this meant a 320x411 window centered within a 320x1528 reservation: 1117px of reserved vertical space outside the visible window. The neighboring application's work area excluded that entire side even where no companion window was visible.

The native helper now places the borderless dock at the negotiated rectangle's top and uses its full height. Godot requests work-area height, rather than content height. Shell negotiation remains authoritative and continues to respect the taskbar and other registered bars. Floating remains a one-shot release, never a geometry-enforcement loop. Collapse remains a 28x96 widget and releases the reservation.

There are three different phenomena:

- The previous centered, short dock inside a full reservation was a real native geometry defect, fixed here.
- Residual gray space inside a correctly sized client is an aspect/layout/content issue. It is partly occupied by the new dashboard; blank space can remain when there are no records.
- A Windows Snap preview is OS-owned. No reference screenshots accompanied this text attachment, so no specific screenshot region can be identified as a Snap preview. Actual physical Snap gestures are not claimed as tested.

All native coordinates were measured with GetWindowRect/GetClientRect/GetMonitorInfo/GetDpiForWindow. The tested monitor is 2560x1600, work area `[0,0,2560,1528]`, DPI 144. Maximized outer rectangles include Windows' invisible resize-border allowance; this is not a project gap. Both native processes use per-monitor-v2 awareness. Display/DPI notifications and redocking on the current monitor retain the existing implementation; physical multi-monitor/mixed-DPI switching remains unverified.

## Shared presentation strategy

Environmental information stays first, in the existing location/weather/day-time/wind/current/tide order. Wide headers are 40px; narrow headers use two 42px rows. Time and wind remain explicitly N/A. No fictional wind service or local-computer time is added.

The upper-right toolbar contains five controls: current Active/Passive mode, Dock window menu, Gear drawer, Menu and Settings. The window menu holds Dock Left, Dock Right, Float and Collapse. Native title-bar controls are not duplicated. Narrow desktop uses two compact toolbar rows, with wider readable actions rather than nine tiny bottom buttons. The current mode button uses the existing controller's cycle action; menu/equipment/settings use existing routes.

The world retains existing 640x480 or 960x480 projection and uniform display scaling. Hysteresis is unchanged (1.75 enter / 1.60 exit, based on available gameplay space). Fishing and collapsed states continue to lock the current world shape. Resize changes no camera transform; normal fishing exit applies deferred shape changes. Docking selects 4:3 when safe.

The optional dashboard is below gameplay and cannot resize it when sections fold. It is shown only with at least 150px spare height and a docked or 4:3 context. Expanded wide defaults to no dashboard. It reads the shared loadout snapshot and `FishingJournalService.get_summary()/get_entries(false)`; owns no gameplay data or persistent counters. Equipment and records sections independently collapse. Their buttons open the existing Equip/Data pages. Records are labeled lifetime, not invented session totals. Undiscovered cards/fish are not revealed. Missing accessory/detail information routes to Equip; no fabricated accessory is shown. The shared pinnable drawer remains available and opens immediately.

At zero catches the records section says so, and remaining height is intentionally not filled with fake statistics or giant empty parchment. A tall minimum dock can still have gray space below its real data. This is an explicit presentation limitation, not a hidden native reservation gap.

## Tall-view experiment: rejected

The disposable QA fixture tested 640x864, with a mathematically equivalent horizontal projection to preserve pixel scale. It changed projection only in the fixture, with zero camera translation, then restored it. Production never uses this experimental projection.

- Player pixel-scale sample: 2.20500946 before and after.
- Player physical-foot projection: `(66.63406,428.9524)` -> `(66.63403,620.9524)`.
- Existing power-bar Y responds to the taller viewport as 729 instead of 405.
- Approved lower-left composition and foot/HUD vertical relationship therefore change.
- Rendered capture exposes a large black sea/beach mesh boundary.

The taller view is visually unsafe without changing the accepted camera/HUD/ground contract, so it is not deployed. Evidence: `build/mobile-web/desktop-responsive/tall-experiment.png` and `.json`.

## Native/rendered measurements

Production frames captured in exploration and active IN_WATER. All dashboard rectangles below are allocated bounds; content panels fit their real text rather than stretching to fill them.

| Case | Native outer rectangle | Client | World display / logical aspect | Header / upper toolbar | Dashboard allocation |
| --- | --- | --- | --- | --- | --- |
| Maximized | [-11,-11,2571,1539] | 2560x1494 | 2548x1274 / 2:1 | 40 / 580x36 at (1976,44) | Hidden; 118px spare |
| Regular floating | [1749,439,2571,1055] | 800x560 | 621.33x466 / 4:3 | 40 / 580x36 at (216,44) | Hidden |
| Half-screen-sized floating | [0,0,1280,1528] | 1258x1472 | 1246x934.5 / 4:3 | 40 / 580x36 at (674,44) | 1246x435.5 |
| Left minimum dock | [0,0,320,1528] | 320x1528 | 308x231 / 4:3 | 84 / 312x72 at (4,88) | 308x1115 |
| Left maximum dock | [0,0,900,1528] | 900x1528 | 888x666 / 4:3 | 40 / 580x36 at (316,44) | 888x760 |
| Right minimum dock | [2240,0,2560,1528] | 320x1528 | 308x231 / 4:3 | 84 / 312x72 at (4,88) | 308x1115 |
| Right maximum dock | [1660,0,2560,1528] | 900x1528 | 888x666 / 4:3 | 40 / 580x36 at (316,44) | 888x760 |

With a left 320/900 dock the neighboring work area is `[320,0,2560,1528]` / `[900,0,2560,1528]`. With a right 320/900 dock it is `[0,0,2240,1528]` / `[0,0,1660,1528]`. Window top/bottom exactly match reservation top/bottom. No reserved vertical gap or taskbar overlap remains.

Compared with v1, minimum dock native height increases from 411 to 1528 and maximum from 766 to 1528. World scale stays width-derived (308x231 / 888x666); it does not zoom to consume height. Maximized gameplay remains 84.9% of its client; regular remains 64.6%. Minimum dock's gameplay share is now 14.6% of the full-height client, with the remaining space used for compact controls and real optional information. Half-screen geometry was sized programmatically using measured native chrome; this is not physical Windows Snap acceptance.

Captures inspected:

- `build/mobile-web/desktop-responsive/{expanded,regular,half-screen,minimum-dock}-{exploration,fishing}.png`
- `build/desktop-docking/fishing-{left,right}-{320,900}.png`
- Native measurement JSON alongside those files and `build/mobile-web/desktop-responsive/measurements.json`.

## Overlay ownership

`ExplorationHud` owns the compass through `Compass_Face.png` / `Compass_Needle.png`; `_on_camera_heading_changed()` rotates the needle with camera yaw. `Compass_Face_Fish.png` is the flashing cast-ready overlay controlled by `set_cast_available()` and the `cast_ready` animation. These are gameplay heading/readiness indicators, not debug wind placeholders, and remain unchanged. A future wind indicator must read a future authoritative service; current UI explicitly reports wind unavailable.

## Verification actually run

Godot executable: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`.

Existing isolated wrappers under `build/mobile-web/root-repair` ran `--headless --path <project>` for `run.py` and `--rendering-method gl_compatibility --path <project>` for `render_run.py`. Native fixtures ran with approval outside the sandbox. Exact script suffixes and results:

| Command suffix | Result |
| --- | --- |
| `--editor --import --quit` | Exit 0 |
| `--script res://scripts/qa/responsive_desktop_ui_qa.gd -- --tall-experiment` (rendered/native) | 106/106 |
| `--script res://scripts/qa/desktop_companion_docking_qa.gd` (rendered/native) | 657/657 |
| `--script res://scripts/qa/desktop_floating_qa.gd` (rendered/native) | 14/14 |
| `--script res://scripts/qa/seaside_shell_layout_qa.gd` | 88/88 |
| `--script res://scripts/qa/fishing_camera_hud_stability_qa.gd -- --desktop` (rendered) | 45/45 |
| `--script res://scripts/qa/fishing_camera_reconstruction_qa.gd` | 124/124 |
| `--script res://scripts/qa/passive_fishing_qa.gd` | 95/95 |
| `--script res://scripts/qa/runtime_lifecycle_qa.gd` | 1832/1832 |
| `--script res://scripts/qa/runtime_lifecycle_qa.gd -- --mobile` | 1052/1052 |
| `--script res://scripts/qa/mobile_landscape_shell_qa.gd` | 455/455 |
| `--script res://scripts/qa/mobile_portrait_harness_qa.gd` | 153/153 |
| `--script res://scripts/qa/mobile_gameplay_parity_qa.gd` | 49/53; unchanged four baseline foot-Y assertions |
| `--script res://scripts/qa/session_contract_runner.gd` | Full fishing 22950/22950, contract PASS, zero orphans |
| `git diff --check` | PASS |

The first v2 render exposed a drawer's quarter-second refresh delay; immediate drawer visibility at the existing action boundary fixes it. That failed run (66/67) is not presented as green. Existing GLES shader-cache diagnostics and unrelated mobile/economy findings remain unsuppressed.

No screenshots were included with the supplied v2 text attachment. Captures here are actual Godot-rendered native-window client images paired with independently measured Win32 rectangles, not whole-desktop screenshots. Physical Snap/title-bar/resize UX approval and multi-monitor/DPI switching still require designer testing. No physical UX approval is claimed. Web was not rebuilt and HTTPS was not restarted.

## Files changed in v2

- `scripts/desktop/desktop_companion.gd`
- `scripts/desktop/companion_dashboard.gd` and generated `.uid` (new)
- `scripts/ui/seaside_shell_layout.gd`
- `scripts/ui/seaside_shell_view.gd`
- `tools/desktop/windows_appbar.py`
- `tools/desktop/inspect_window.py` (new read-only QA witness)
- `scripts/qa/desktop_companion_docking_qa.gd`
- `scripts/qa/responsive_desktop_ui_qa.gd`
- `docs/qa/desktop_companion_v2.md` (new)

Previously dirty v1 environmental-strip QA/resource/report files and the responsive QA UID were preserved, not edited as part of v2.
