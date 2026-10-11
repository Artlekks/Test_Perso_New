# Responsive Mobile UI v3 — verification

Implemented 2026-10-11 with installed Godot 4.7.2. Physical Safari acceptance is still required; these screenshots are actual native Compatibility renders, not phone captures.

## Root causes and implementation

V2 constrained landscape to 640×480 and allocated relatively tall headers/control panels. More seriously, the Web canvas uses high-DPI backing pixels while the shell previously disabled logical scaling. A nominal 44-unit control could therefore be much smaller than 44 CSS pixels on an iPhone. The harness now derives its logical Window content size from browser `innerWidth/innerHeight`, independently of backing resolution. CSS safe-area insets use the same units. A real 3x Window/input fixture verifies the conversion, including balanced ScreenTouch action delivery.

Landscape now renders the actual world at **960×480**, with the authored Camera3D KEEP_HEIGHT projection. Vertical projection, camera pose/FOV and world-space actor position do not change. A world point in the old frame gains 160 pixels on either side; objects beyond the old frame become visible. Portrait and desktop remain **640×480**. Orientation changes remap the cached fishing screen anchor mathematically; they do not reset or replace camera tracking. Camera, fishing mechanics and desktop window-management scripts were not changed.

Full menus retain their separate 640×864 canvas. On landscape, they are centered and uniformly scaled at the world's vertical pixel scale. The shared equipment drawer remains independent of viewport geometry, with existing pin/modal restoration and authoritative unified lure/bait data.

The wider lens exposed the finite beach GLB's edges. A single scene-owned, non-blocking landscape-only MeshInstance3D extends ground/water underneath it, sampling the existing `assets/models/textures/Beach.png` sand and water patches. The 64×64 backing uses the existing ShoreBlocker's world Z to select land versus water. No art was generated, no collision added and no actor moved. Portrait retains the original mesh view. Rendered edge-sample assertions and screenshot inspection verify the wider frame no longer exposes black ground/water voids. This is visual backing, not new playable terrain.

Both orientations share geometry and controls. Portrait now has a parchment lower control surface with substantially larger face buttons and analog stick. The environmental strip is 64 logical pixels tall in landscape and 104 in portrait; text uses the existing font with continuous fixed-size scaling, at 18/16/14 logical pixels (constrained spot name 16). Label simplification precedes numeric/value removal. Wind and day/clock remain explicitly unavailable. Current, tide, weather and location use existing sources.

Mappings remain A→K, B→I, X→one named card-challenge action, Y→J, L/R→Q/E, Start→existing Space pause. Select/Gear open the shared equipment drawer/Settings. The input adapter, steering strengths and multitouch reference counts remain intact.

## Geometry measured from rendered execution

Reference safe insets: landscape 47 left/right and 21 bottom; portrait 47 top and 34 bottom. Safari's actual CSS insets override these reference fallbacks. Area percentage includes header and controls in its denominator. Before values are the previous V2 native measurements; those alone did not prove physical CSS control sizes.

| Browser/reference size | V2 displayed game | V3 displayed game | Game/safe area | Game/safe width | Joystick diameter | X/Y/B diameter; A diameter | Fallback |
|---|---|---|---|---|---|---|---|
| 568×320 | 258×193.5 | 446×223 | 70.2% | 94.1% | 100 | 44; 49.28 | Edge overlay |
| 667×375 | 357×267.75 | 556×278 | 76.2% | 97.0% | 100 | 44; 49.28 | Edge overlay |
| 844×390 | 406.67×305 | 506×253 | 46.3% | 67.5% | 100 | 44; 49.28 | Separate islands |
| 932×430 | 460×345 | 594×297 | 51.5% | 70.9% | 100 | 44; 49.28 | Separate islands |
| 320×568 | 228×171 | 308×231 | 45.7% | 96.3% | 116 | 44; 49.28 | Scroll controls |
| 375×667 | 360×270 | 363×272.25 | 45.0% | 96.8% | 116 | 44; 49.28 | Scroll controls |
| 390×844 | 378×283.5 | 378×283.5 | 36.0% | 96.9% | 130 | 65.36; 73.2 | None |
| 430×932 | 418×313.5 | 418×313.5 | 35.8% | 97.2% | 130 | 72.5; 81.2 | None |

Sizes are CSS/logical pixels after high-DPI normalization. Face hit circles and visible circles have the listed diameter; the analog visible circle is slightly inset (4 px radius) from its listed hit diameter. L/R, Start, Select and Gear have minimum 44-pixel height. Landscape controls use 104/128-pixel-wide left/right islands, not giant decorative panels. Large portrait spaces are now used for larger controls and parchment rather than an empty dark panel.

At 568/667 landscape, the explicit fallback overlays controls on the outer portions of the world. It maximizes world width while retaining 44-pixel buttons and a 100-pixel stick. It necessarily obscures peripheral scenery; native fishing-entry renders were inspected. Physical Safari checks during active fights remain necessary. Normal 844/932 layouts keep permanent controls outside gameplay.

At 320/375 portrait, full-width gameplay, readable header and all preferred controls cannot fit simultaneously. Only the lower control surface scrolls; gameplay never crops or scrolls. Drag its empty central seam to reveal the footer, or use the scrollbar. All face controls can be shown together; shoulders and footer cannot all be visible simultaneously on the shortest size. The seam explicitly excludes buttons, utility targets and stick ownership. Real ScreenTouch/ScreenDrag QA verifies scrolling, not just property assignment. The minimum content height is 224 pixels. A shorter readable header could reduce this conflict in a future design pass.

The wider landscape reduces displayed vertical height at the same safe width; it trades some per-world-pixel scale for more horizontal environment. Fishing HUD clearance/visibility remains governed by existing systems. Physical HUD text readability at the smallest fallback size is not asserted from native geometry tests.

## Rendered evidence

Artifacts: `build/mobile-web/ui-v3/` (ignored QA output).

- `explore-WxH.png`, `fishing-WxH.png`, `drawer-WxH.png`, `modal-WxH.png`: all eight requested sizes, inspected with representative modal/drawer views.
- `world-640.png` and `world-960.png`: same physical camera/actor pose, real wider horizontal world.
- `controls-scroll-320x568.png`, `controls-scroll-375x667.png` and corresponding `controls-footer-*.png`: reachable short-portrait control states.
- `geometry.json`: raw measurements.

These show no stretching, large control islands and readable compact environmental values. Native visual inspection does not establish thumb comfort, Safari toolbar behavior or physical phone acceptance.

## Executed QA

Executable: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`, using `--path` at the current project. Scratch wrappers redirect APPDATA/LOCALAPPDATA to ignored `build/mobile-web/root-repair/`; fixtures use disposable profiles.

| Godot arguments | Result |
|---|---|
| `--headless --editor --import --quit` | Exit 0, no script compilation errors |
| `--rendering-method gl_compatibility --script res://scripts/qa/mobile_landscape_shell_qa.gd` | 434/434: eight sizes, touch/action ownership, drawer/pin/modals, DEV match, fishing entry, teardown |
| `--rendering-method gl_compatibility --script res://scripts/qa/mobile_surface_projection_qa.gd` | 47/47: real projection, unchanged camera/actor, rendered world-edge samples, 3x CSS input, portrait scroll drag and input exclusion, footer reachability |
| `--headless --script res://scripts/qa/mobile_portrait_harness_qa.gd` | 153/153: touch/multitouch, dialogue/merchant/card gates, pause, travel |
| `--headless --script res://scripts/qa/seaside_shell_layout_qa.gd` | 88/88: shared shell, unchanged desktop |
| `--headless res://actors/mobile/MobileWebParityQA.tscn` | 36/36: native execution of Web-capable fixture, not browser DOM execution |
| `--headless --script res://scripts/qa/fishing_camera_reconstruction_qa.gd` | 124/124 |
| Same reconstruction command with `-- --wide` | 124/124 at 960×480 |
| `--headless --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd` | 199/199 |
| `--headless --script res://scripts/qa/fishing_water_camera_qa.gd` | 16/16 |
| `--headless --script res://scripts/qa/runtime_lifecycle_qa.gd -- --mobile` | 1052/1052, full fishing 22950/22950; structural nodes/resources stabilize, one service, zero orphans |
| `--headless --script res://scripts/qa/session_contract_runner.gd` | PASS; full fishing 22950/22950, Triple Triad backend 101/101, zero orphan nodes |
| `--headless --script res://scripts/qa/mobile_gameplay_parity_qa.gd` | 49/53: four existing synthetic fight-yaw foot-Y failures unchanged |
| `git diff --check` | PASS |

QA expectations changed only for deliberate new geometry/parenting. The Web-capable fixture now also declares a real phone-sized logical canvas for the headless DisplayServer's 64×64 dummy window; its actual touch and card assertions remain. An initial attempt to invoke that Node-based fixture with `--script` was stopped; the correct scene invocation above was used. Initial scroll-drag failures were fixed in production, not waived.

Existing balance findings remain 22/24 with the two H12 alerts. Rendered runs retain existing engine GLES shader-cache write diagnostics (`_save_to_cache`, `f.is_null()`); they are not suppressed. Reconstruction QA intentionally exercises incompatible framing and prints its expected safety diagnostic. Four pre-existing foot-Y parity failures remain separate from this UI pass.

## Changed files

V3 runtime edits: `scripts/ui/canonical_game_surface.gd`, `scripts/ui/seaside_shell_layout.gd`, `scripts/ui/seaside_shell_view.gd`, `scripts/ui/seaside_environment_strip.gd`, `scripts/mobile/mobile_portrait_harness.gd`, `scripts/mobile/mobile_touch_controls.gd`.

New runtime files: `scripts/mobile/mobile_world_ground_extension.gd`, `assets/models/shaders/landscape_ground_extension.gdshader`, and their generated `.uid` companions.

QA edits: `scripts/qa/mobile_landscape_shell_qa.gd`, `scripts/qa/mobile_portrait_harness_qa.gd`, `scripts/qa/mobile_web_parity_qa.gd`, `scripts/qa/seaside_shell_layout_qa.gd`, `scripts/qa/fishing_camera_reconstruction_qa.gd`. New QA: `scripts/qa/mobile_surface_projection_qa.gd` and `.uid`.

Documentation: this report. The already-dirty V2 report and two existing untracked V2 UID files were retained. Web rebuild modifies `export/index.html` and `export/index.pck`; byte-identical JS/WASM do not appear as changed files.

## Delivery

Use existing `& .\tools\mobile\build_mobile_playtest.ps1` for the validated WSL/Linux Godot 4.7.2 preset. No HTTPS restart or server/certificate change. Post-export PCK validation remains mandatory. Refresh the existing Safari URL after successful export.

Final export completed successfully: `export/index.pck` **32,573,452 bytes**, internal `project.binary` **9,970 bytes**, valid **ECFG** header. The final world-edge correction was rendered and checked before this rebuild. `index.js` and `index.wasm` remain byte-identical to the existing exporter output.

Physical acceptance: both orientations with Safari toolbars/cutouts; simultaneous stick plus face buttons; smallest-screen scroll seam/footer; drawer pin/unpin and Settings; active bait/fight HUD clearance and readability; lower-left fishing composition while rotating orientation; card challenge and modal release.
