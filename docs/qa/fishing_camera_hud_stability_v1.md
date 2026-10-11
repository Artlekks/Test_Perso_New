# Fishing camera stability and responsive HUD alignment

## Scope and root cause

Preserved Mobile UI v3.1, portrait 640x480, landscape 960x480, camera pitch/framing, cast handoff, input mapping, hooked-fish mechanics, and sea continuation. No shell or mobile runtime files were edited in this pass.

`CameraRig._update_fight_camera_tracking()` formerly called `_bounded_anchor_dolly()` and then `_bounded_ground_pan()` for **vertical violations even in ANCHORED**. The empty-lure path was already yaw-only; the hooked/generic target path was not. This explains a reproducible source of zoom-like motion, rather than a FOV change. An ignored diagnostic loaded the unchanged pre-pass camera script from Git and applied the same target at (320, 338.4) to both versions:

| Version | Camera-to-player distance before | After | Dolly | Pan |
|---|---:|---:|---:|---|
| Before | 7.21110249 | 7.33459425 | 0.01712523 | (0,0) |
| Repaired | 7.21110249 | 7.21110249 | 0 | (0,0) |

This reproduces the defective anchored path. It does not establish which exact state occurred in the user's earlier Safari playtest; a purely empty-lure IN_WATER path was already free of dolly. That distinction remains explicit.

TRAVEL retains its existing bounded translation/handoff. Once ANCHORED, only player-pivot yaw can respond to the bait. Empty-lure handback retains any already-latched travel pan instead of silently dropping it. Cast entry, complete-retrieve exponential unwind, catch/result ownership, and exploration restoration retain their existing owners. Incompatible vertical target positions still report framing failures; they cannot authorize zoom or be silently marked healthy. Old tests demanding anchored vertical dolly were corrected to require the new no-dolly contract, preserving target immutability and failure diagnostics.

Unchanged tuning: free-lure maximum yaw 7 degrees; combat maximum 55 degrees; tracking response 6/s; retrieve return response 2/s. No FOV, pitch, roll, camera distance, fishing physics, or combat-input tuning was made.

## HUD ownership and measured placement

The previous PowerMeterView/DepthMeterView cached independent absolute resting positions. Width 960 therefore retained x=175/532 from width 640. Position tweens also carried absolute destinations through a resize.

PowerMeterView now owns both resting positions, using the **actual CanvasLayer custom viewport** where present. The vertical-meter origin retains x/viewport_width = 532/640. Both gauges translate by the same width-dependent amount, preserving their authored 357px origin separation and actual approximately 9.8px artwork gap. The power artwork remains 347.2x56, scale (.35,.35); meter artwork remains approximately 47.52x102.24, scale (.36,.36). No texture stretching or per-phase resting layout is introduced.

Existing entry/exit animation durations and easing remain. Tweens now animate presentation progress into the responsive resting composition, so orientation changes cannot leave a cached absolute tween endpoint. DepthMeterView owns its slide progress, not the shared resting layout.

| Gameplay viewport | Power before (x,y,w,h) | Power after | Meter before | Meter after |
|---|---|---|---|---|
| 640x480 | 175,405,347.2,56 | unchanged | 532,354,47.52,102.24 | unchanged |
| 960x480 | 175,405,347.2,56 | 441,405,347.2,56 | 532,354,47.52,102.24 | 798,354,47.52,102.24 |

Normalized after rectangles:

| Viewport | Power (x,y,w,h) | Meter (x,y,w,h) | Player physical anchor (x,y) |
|---|---|---|---|
| 640x480 | .273438,.843750,.542500,.116667 | .831250,.737500,.074252,.213000 | .104116,.893650 |
| 960x480 | .459375,.843750,.361667,.116667 | .831250,.737500,.049501,.213000 | .236077,.893650 |

Rendered sprite/rod silhouette bounds in the selected reel frame: portrait (.076563,.556250,.154687,.335417), landscape (.217708,.556250,.103125,.335417). These include the animation's rod, and are measured by rendering the sprite visible/hidden in the same engine frame, avoiding assumptions about atlas margins or billboard transforms.

Real mobile-scene camera measurements: origin distance 1.45495689, optical distance including offsets 2.01660180, FOV 75 degrees, pitch 66 degrees, roll 0, optical offsets (.9,.65), unorbited world offset (.450397,1.38,.098192). Edge yaw is allowed; these non-yaw quantities and the physical player projection remain constant within 0.0001 world units / 0.00001 normalized projection tolerance. Camera projection size 1 is recorded but inactive for the perspective camera.

## Empty-lure steering

First press already receives full steering before physics; there is no new impulse/event path. Existing lateral gain 1.175, inward gain 1.10 and A/D retrieve ratio .45 remain. The weak short-tap contribution was curtailed by the 10/s release damping (and steering magnitude also scales inward speed). Empty lures now use an exported `free_steering_return_speed = 8/s`, a modest longer release tail. Combat retains its original `reel_steering_return_speed = 10/s` and rod-dependent response. Repeated taps, monotonic relaxation, uninterrupted inward progress and near-shore arcs are covered.

## Commands and results

Native executable: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe` (4.7.2.stable.official.ed1daf0bf). Commands below ran through `build/mobile-web/root-repair/run.py` for headless or `render_run.py` for Compatibility rendering; wrappers redirect APPDATA/LOCALAPPDATA into ignored scratch. Each command uses `--path` to this project. Logs are under that same scratch directory with the recorded names.

| Arguments | Log prefix | Result |
|---|---|---|
| `--headless --editor --import --quit` | camera-hud-import-delivery | exit 0; no script compilation errors |
| `--rendering-method gl_compatibility --script res://scripts/qa/fishing_camera_hud_stability_qa.gd` | camera-hud-render-delivery | 79/79 |
| `--headless --script res://scripts/qa/empty_lure_retrieval_qa.gd` | camera-hud-empty-delivery | 286/286 |
| `--headless --script res://scripts/qa/fishing_camera_reconstruction_qa.gd` | camera-hud-reconstruction | 124/124 |
| same, `-- --wide` | camera-hud-reconstruction-wide | 124/124 |
| `--headless --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd` | camera-hud-fight-final | 199/199 |
| `--rendering-method gl_compatibility --script res://scripts/qa/mobile_surface_projection_qa.gd` | camera-hud-projection-render | 334/334 |
| `--rendering-method gl_compatibility --script res://scripts/qa/mobile_landscape_shell_qa.gd` | camera-hud-shell-render | 455/455 |
| `--headless --script res://scripts/qa/mobile_portrait_harness_qa.gd` | camera-hud-mobile-touch | 153/153 |
| `--headless --script res://scripts/qa/fishing_presentation_current_polish_qa.gd` | camera-hud-presentation | 194/194 |
| `--headless --script res://scripts/qa/passive_fishing_qa.gd` | camera-hud-passive | 95/95 |
| `--headless --script res://scripts/qa/runtime_lifecycle_qa.gd -- --mobile` | camera-hud-lifecycle, camera-hud-lifecycle-repeat | first 1051/1052; repeat 1052/1052 |
| `--headless --script res://scripts/qa/mobile_gameplay_parity_qa.gd` | camera-hud-parity | 49/53; same four pre-existing foot-Y assertions |
| `--headless --script res://scripts/qa/session_contract_runner.gd` | camera-hud-full | full fishing 22950/22950, fight 24/24, presentation 10/10, bite timing 14/14, stability 27/27, Triple Triad 101/101; zero orphan nodes |
| `git diff --check` | terminal | exit 0; CRLF notices only |

The first lifecycle run exceeded the normalized object-count allowance by one object in cycle 4; the other cycles returned within the bound. The repeat passed unchanged. Both runs retained structural nodes 2256, resources 2236, one session service, zero orphans, four timers/one active timer, 42 connections and zero settled tweens. This intermittent object-count diagnostic is recorded, not suppressed or claimed resolved by this pass.

An exploratory **headless** projection run reported 48/50 because its dummy renderer cannot satisfy rendered horizontal-FOV assertions. The required Compatibility-rendered projection run passes 334/334; headless output is not presented as visual evidence. Rendered runs still emit the previously documented GLES shader-cache filesystem diagnostics. Dedicated impossible-framing QA deliberately emits safe-region/HUD diagnostics. Known 22/24 H12 balance alerts remain unchanged.

Screenshots and full measurements: `build/mobile-web/camera-hud-stability/` (390x844, 932x430, 320x568, 568x320). The existing shell fixture also rendered all eight reference CSS sizes into `build/mobile-web/ui-v3/`. Inspected both orientations and constrained-size geometry. These are native Compatibility rendered captures, not physical Safari acceptance.

## Files changed in this pass

- scripts/camera_rig.gd
- scripts/bait_V2.gd
- scripts/power_meter_view.gd
- scripts/depth_meter_view.gd
- scripts/qa/empty_lure_retrieval_qa.gd
- scripts/qa/fishing_camera_reconstruction_qa.gd (retains its earlier wide-viewport support)
- scripts/qa/fishing_fight_camera_tracking_qa.gd
- scripts/qa/fishing_camera_hud_stability_qa.gd and generated .uid (new)
- docs/qa/fishing_camera_hud_stability_v1.md (new)
- export/index.html, export/index.pck (regenerated)

All other pre-existing dirty files were left untouched.

## Web delivery and remaining acceptance

Ran `.\tools\mobile\build_mobile_playtest.ps1` with the existing Linux/WSL Godot 4.7.2 exporter and Mobile Portrait Web Playtest preset. Validated PCK: **32,584,400 bytes**; internal project.binary **9,970 bytes**, valid **ECFG** header. Existing HTTPS was neither started nor restarted. Refresh the existing Safari address.

Still requires physical phone acceptance: short-tap feel, combined A/D+K near shore, a normal hooked fight, result dismissal, and exit in both orientations. Synthetic targets outside yaw-only achievable framing continue to report diagnostics; this pass does not claim that unconstrained vertical targets can always be recovered by yaw. No gameplay bounds or combat rules were changed to mask that limitation.
