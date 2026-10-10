# Morning Stability & UX Pass v1

## Contracts and root causes

1. **Camera:** the old shared tracking latch stayed active beyond its original
   edge; the bidirectional orbit search could choose an opposite heading while
   the bait was returning centrally. Orbit projection could also compound yaw
   when evaluated against an already-orbited optical transform. Projection now
   uses the neutral fishing optical pose, and the solver searches only in the
   corrective direction of the active edge.
2. **Edge state:** HOLD, PAN_LEFT and PAN_RIGHT own independent edge behavior.
   Crossing x<.12 or x>.92 activates; reaching .14 or .90 respectively stops
   when vertically safe. Touching the outer boundary alone does not activate.
   HOLD preserves the exact yaw, with no neutral return or target chasing.
   Vertical bounds .08–.75 and vertical margin .025 preserve HUD protection.
   Current and Passive physical bait positions use the same logic. Response 6,
   retrieve return response 2, ±55°, IN_WATER/FIGHT eligibility and A/D are unchanged.
3. **Modal leakage:** restoring SceneTree pause allowed closing events to resume
   gameplay dispatch. A held-action snapshot also missed queued forwarded
   events. ModalInputGate consumes closing input before unpause, waits for an
   observed release, and admits a fresh press after the closing process frame.
   World consumers observe releases even during pause; the interaction router
   clears its claimed-key latch rather than retaining a stale C. Manual Space
   pause has an explicit release path. No timed cooldown is used.
4. **Deck editing:** K begins editing the exact selected slot, filled or empty.
   The source slot stays identified while browsing. Choosing its current card
   removes membership only; Back cancels without mutation. Replacing a filled
   slot in a short deck replaces that slot instead of appending. The existing
   compact save schema remains: removals pack surviving entries left, leaving
   trailing empty slots. Collection ownership, legality and six profiles remain
   authoritative in the existing backend.
5. **Selectors:** deck and collection outlines are independent white-modulated
   sibling panels at z=1000. They do not inherit card darkening. Pools are created
   at setup, avoiding growth on successive matches. Menu borders use the approved
   Menu_Hint_Panel_Selector.png, nearest filtering, border-only NinePatchRect at
   z=2 above row content. No new selector artwork.
6. **Catch centering:** Data, rank and lifetime points share one group. The points
   label was outside the authored points area; it now sits inside that area.
   The group center uses actual gameplay presentation bounds. The mobile harness
   publishes visible logical crop height, excluding touch controls. Desktop
   mapping uses the uniformly scaled gameplay image, excluding chrome/letterbox.
   Item/card notices retain their existing variant-specific presentation.
7. **Dock jump:** Godot wrote client sizes while the sidecar asynchronously wrote
   the native rectangle; combining new sizes with previous origins exposed an
   intermediate wrong edge. A hidden reservation window also left the companion
   classified as an ordinary window, allowing Windows to relocate it into the
   reduced work area before native positioning. These were actual sampled native
   rectangle errors, not only stale Godot position/size caches.
8. **Dock ownership:** the sidecar registers the actual companion HWND and gives
   the dock the native tool-window role. Only the sidecar writes dock/widget
   rectangles. Godot stores desired width and consumes acknowledgements without
   issuing a second resize. Both processes use physical per-monitor coordinates.
   IPC reads allow atomic replacement; publication failures retry without Float.
   The invisible inner hit target is 8 pixels. Following physical feedback about
   lag, changed widths now publish once per rendered drag frame and the native
   command poll is 8 ms; idle status polling remains 50 ms.
9. **Collapse/Float:** collapse removes the entire reservation and overlays a
   28×96 edge tab. Restore remembers width/side and reacquires reservation.
   Floating restore shares the ordered native widget command stream, preventing
   late collapse commands from shrinking an expanded window. Float keeps the
   current client rectangle, not a historical floating location. Normal movable/
   resizable decoration returns only after AppBar release so Windows does not
   relocate it into the old reserved area. Unused shell fill is dark gray.
10. **Passive timer:** auto-entry/cast is preserved. One second after water entry,
    CONFIGURING displays a clickable timer above the power bar. `20` means 20
    minutes; MM:SS accepts seconds 0–59. Enter/K confirms in context. Only then
    does the monotonic focus countdown plus existing opportunity delay begin.
    QA can explicitly disable confirmation for short automated schedules.
11. **Ripple:** fish_ripple.png source/SpriteFrames are unchanged; ripple pixel
    size is .00175, half .0035. Strong splash size remains unchanged. Opportunity
    ripple lifetime still matches hook timing; missed opportunity cleans up;
    committed take uses splash, never mere hook readiness.
12. **Engagement:** ready INSPECT candidates use exported
    engaged_bite_opportunity_chance=.70. Ambient nearby shadows retain ambient
    probability. The unused 1.30 multiplier was removed to avoid two conflicting
    inspector controls. Fish selection, lure/depth eligibility and rewards are unchanged.
13. **Hands:** both hand stacks use 39.6-pixel vertical steps, 30% of the existing
    132-pixel card height. Dimensions 116×132 and animation speed are unchanged.
14. **Crafting details:** recipe/header navigation remains scrollable, with the
    recipe/material and result/inventory stack a separate fixed sibling at y=236.
    Selection-follow scrolling cannot move that stack.

## Verification

All QA uses disposable profiles. No production save is reset. The LAN HTTPS
server is never restarted. Full results/logs are under build/desktop-docking/.

| Suite | Result |
|---|---:|
| Fight camera native / mobile policy | 189/189 each |
| Morning modal/deck/menu/timer/engagement QA | 205/205 |
| Rendered mobile native edge sequence | 1344/1344 |
| Rendered Web edge sequence, 390×664 | 1344/1344 |
| Rendered companion edge/collapse/result sequence | 1388/1388 |
| Passive Fishing | 55/55 |
| Deck ownership/save durability | 91/91 |
| Mobile harness / presentation | 162/162; 252/252 |
| World interaction / dialogue readability | 93/93; 125/125 |
| Session composition, 12 alternating hosts | 102/102 |
| Native / mobile lifecycle | 1832/1832; 1052/1052 |
| Developer Playtest | 90/90 |
| Full fishing regression, native and mobile lifecycle | 22950/22950 each |
| Triple Triad / dialogue / crafting / Card Maker | 101/101; 175/175; 14/14; 10/10 |
| Fight / presentation / bite timing / stability / fresh save | 24/24; 10/10; 14/14; 27/27; 55/55 |
| Native dock/Float/collapse/catch centering | 587/587 |
| Native work-area/crash/normal-close/continuous-edge witness | 4/4; 2120 physical samples, zero edge errors |

Native and Web sequences run three real casts, misses, retrieve, hook, landing,
result dismissal and exit. The fixture moves only its isolated physical target
for deterministic edge coverage. Each sequence runs left→center→right→center
and the reverse without resetting yaw between edges, asserting exact camera
transform equality on every central frame. Existing production movement and
animation callbacks run outside those target-placement steps.

The first Web attempt timed out during Prep_Fishing under background frame
throttling. It did not reach camera QA and is not counted as a pass. Acceptance
waits now use simulation time plus an independent wall-clock stall watchdog;
foreground rendered Web execution subsequently passed all 1326 assertions.

The final batch caught one stale Passive fixture assumption: it checked the
expanded rectangle immediately after requesting asynchronous native restoration.
It now waits for acknowledgement and checks the same exact rectangle before
switching Active. No geometry assertion was relaxed; an additional restoration
assertion raised the suite from 54 to 55 checks.

Physical designer acceptance confirmed dock left/right resize and collapse
worked without jumps. The reported stepped/laggy drag led to the per-frame/8 ms
transport change. Native physical-edge sampling checks atomic GetWindowRect,
not separately cached Godot WM_MOVE/WM_SIZE values. Failed GetWindowRect after
intentional process termination is excluded as a dead window, never as a valid
resize sample. Multi-monitor/DPI hardware and final drag smoothness still merit
physical acceptance; this machine has one tested 2560-pixel monitor.

Unrelated GLES shader-cache write diagnostics remain visible in native rendered
logs. Existing text-path UID fallback warnings also remain visible in Web logs.
No project assertions or engine diagnostics were suppressed. Dedicated balance
guardrails remain 22/24 with their known H12 alerts; no balance ceilings changed.

## Commands

Set installed tools:

```powershell
$Godot = "$env:USERPROFILE\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe"
$Python = "$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
```

Each QA script in the results table was run with:

```powershell
& $Godot --path . --rendering-method gl_compatibility --script res://scripts/qa/<suite>.gd
```

Headless suites add --headless; mobile lifecycle/camera add `-- --mobile`.
The reproducible rendered and native ownership commands are:

```powershell
& $Godot --path . --rendering-method gl_compatibility --script res://scripts/qa/portrait_fishing_acceptance_runner.gd -- --edge-pan
& $Godot --path . --rendering-method gl_compatibility --script res://scripts/qa/portrait_fishing_acceptance_runner.gd -- --companion --edge-pan
& $Python tools/desktop/verify_companion_docking.py --godot $Godot
& tools/mobile/build_mobile_playtest.ps1
git diff --check
```

Web acceptance uses the existing FishingCameraDeadZoneQA.tscn in an isolated
Linux export served on localhost:8077, with the browser set to 390×664. Console
reports 1344/1344, casts=3, failures=[]. The production export keeps its normal
main scene. Temporary QA source exports and native drag fixture are build/
artifacts and do not enter production export.

## 15. Changed-file manifest

44 modified/new files. Build/ captures and disposable QA logs
are ignored artifacts, not production source changes.

```text
docs/architecture/deck_ownership_save_durability_v1.md
docs/gameplay/passive_fishing_v1.md
docs/platform/desktop_companion_windowing_v2.md
docs/qa/morning_stability_ux_v1.md
docs/ui/canonical_portrait_stabilization_v1_1.md
export/index.html
export/index.pck
project.godot
scripts/beach_crafting_menu.gd
scripts/camera_rig.gd
scripts/desktop/companion_window_platform.gd
scripts/desktop/desktop_companion.gd
scripts/dialogue/dialogue_controller.gd
scripts/economy/fishing_card_maker_menu.gd
scripts/encounter.gd
scripts/exploration.gd
scripts/fishing.gd
scripts/fishing_catch_view.gd
scripts/fishing_debug_controller.gd
scripts/fishing_economy_menu.gd
scripts/fishing_fight_camera_tracking.gd
scripts/fishing_menu.gd
scripts/fishing_pause_controller.gd
scripts/gameplay/passive_fishing_controller.gd
scripts/mobile/mobile_portrait_harness.gd
scripts/mobile/responsive_menu_surface.gd
scripts/qa/desktop_companion_docking_qa.gd
scripts/qa/fishing_fight_camera_tracking_qa.gd
scripts/qa/mobile_portrait_harness_qa.gd
scripts/qa/morning_stability_qa.gd
scripts/qa/morning_stability_qa.gd.uid
scripts/qa/passive_fishing_qa.gd
scripts/qa/portrait_fishing_acceptance.gd
scripts/qa/portrait_fishing_acceptance_runner.gd
scripts/quests/world_request_journal.gd
scripts/ripple_view.gd
scripts/triple_triad/triple_triad_deck_setup.gd
scripts/triple_triad/triple_triad_game.gd
scripts/triple_triad/triple_triad_presentation_controller.gd
scripts/ui/modal_input_ownership.gd
scripts/ui/modal_input_ownership.gd.uid
scripts/world_interaction_router.gd
tools/desktop/verify_companion_docking.py
tools/desktop/windows_appbar.py
```

## 16. Final QA status

Required suites are green after the fixes above. `git diff --check` passes.
Rendered deck evidence shows both selectors simultaneously, including the
darkened collection card. Crafting evidence confirms the fixed detail stack.
Native catch captures cover left/right at 360 and 620 pixel widths.

## 17. Final Web export

The Linux/WSL build was regenerated and validated: index.pck **32,251,440 bytes**;
project.binary **9,970 bytes**, header **ECFG**. Normal production main scene and
Mobile Portrait Web Playtest preset are preserved. Refresh Safari at the existing
HTTPS address. No HTTPS restart, certificate, server or gameplay mapping changes.

Final physical follow-up: the designer confirmed jump-free resize/collapse.
The faster per-frame/8 ms transport was added after the lag feedback; its outer
edge remains verified, but final tactile smoothness should be checked on the
designer's desktop. No mixed-monitor/DPI hardware acceptance is claimed.
The final latch tests explicitly enter the configured central safe rectangle
from an already-active left/right pan, at two heights derived from each host's
authored vertical bounds. Native rendered fixtures also assert exact hold on
that entry before the 60-frame central drift. An experimental unconditional
horizontal stop failed the existing HUD-clearance assertion and was rejected;
no existing HUD test was weakened. The central safe rectangle holds exactly,
while a target below the HUD-safe boundary remains outside that safe rectangle.
