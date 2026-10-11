# Mobile UI v3.1 — verification

Verified 2026-10-11 with installed Godot 4.7.2. This pass refines v3 without changing camera, fishing, card, economy, desktop or environmental-service code.

## Verified environment root cause

Native rendered on/off comparisons reproduced the reported diagonal striped polygon in the actual fishing view. The v3 `MobileLandscapeGroundExtension` flat plane sat at world **Y −0.272522**, derived from the lowest beach vertex minus 0.015. The existing sloping Sea spans **Y −0.533119 to −0.254362**. The plane therefore cut through the actual water surface. Its `fract(world_xz*2)` tiling of a tiny Beach.png water patch differed from the existing Sea material, making the intersecting region conspicuous. Disabling only that plane removed the striped polygon. No camera/projection change was needed.

Removed the plane and its `landscape_ground_extension.gdshader`/UID. The same scene-owned helper now continues the actual Beach/Sea meshes laterally: two copies on each side reuse the exact authored vertex heights, UV arrays and existing materials. Their boundaries meet the original edges, with no overlapping central water plane. Five inland strips continue only the dry, flat rear land boundary; they inherit authored edge UVs and sample the existing Beach.png sand grain with an edge blend. The new inland shader never renders water or changes the original sea shader. Thirteen static visual children are bounded per scene; no physics, actor movement or per-frame geometry creation. The extensions hide in portrait and are never used by desktop.

Rendered continuity QA compares actual original Sea triangle-centroid pixels with the extensions shown/hidden at three water-facing camera positions. Those pixels remain identical within 0.002 RGB-vector epsilon. This catches the original central-water occlusion/retexturing problem; merely checking for non-black pixels would not. It also checks exact mesh/material reuse and real viewport edges. Screenshots were inspected in exploration and actual waterborne casts, including nibble/MISS presentation during the run.

## UI refinements and measurements

Landscape header **64→40 CSS/logical pixels**. Normal widths show thumbnail/location, weather, clock unavailable, wind unavailable, current and tide on one row. Minimum column widths are based on readable 14-pixel font measurements, not just percentages. Narrow screens put the location alone on two lines; environmental values remain one row. Speed units abbreviate away only in the constrained current cell, retaining direction and numeric strength. Authoritative location remains **Beach**, not an invented rename to Seaside Beach. Wind and day/clock remain explicit N/A. Portrait header stays 104 pixels.

Landscape controls keep their existing islands/fallback. Reduced decorative gaps and the left island's empty margin without reducing its 100-pixel stick. Header savings permit substantial extra height on the constrained sizes; normal sizes remain horizontally limited by usable controls and gain four pixels of game height. Returning all 24 header pixels to those width-limited 2:1 games would require changing the approved control arrangement or overlapping more gameplay, so that was not done.

| Screen | V3 game | V3.1 game | Height gain | V3.1 X/Y/B target | V3.1 A target |
|---|---|---|---|---|---|
| 568×320 | 446×223 | 466×233 | 10 | 47.8 | 53.54 |
| 667×375 | 556×278 | 565×282.5 | 4.5 | 47.8 | 53.54 |
| 844×390 | 506×253 | 514×257 | 4 | 47.8 | 53.54 |
| 932×430 | 594×297 | 602×301 | 4 | 47.8 | 53.54 |
| 320×568 | 308×231 | unchanged | 0 | 48.95 | 54.82 |
| 375×667 | 363×272.25 | unchanged | 0 | 48.95 | 54.82 |
| 390×844 | 378×283.5 | unchanged | 0 | 70.85 | 79.36 |
| 430×932 | 418×313.5 | unchanged | 0 | 78.67 | 88.11 |

Landscape X/Y/B targets were 44, A 49.28: now 8.6% larger. Portrait X/Y/B were 44/44/65.36/72.5 respectively; A was 49.28/49.28/73.2/81.2. The larger portrait values are 8.4–11.2% larger.

Artwork occupies the corresponding target rectangle. Existing transparent PNG margins remain: landscape painted extents are approximately X **44.67×45.50**, Y/B **45.08×45.93**, A **50.92×51.68** pixels, versus approximately 41.12×41.88, 41.50×42.28, 46.87×47.57 before. These derive from existing asset alpha bounds; no art was regenerated.

The union of all face artwork rectangles centers on the right region within **0.01 px** in every tested size. The shared center shifts left by `face*0.03` to compensate for larger A. Opposing center distances are symmetric; adjacent circles retain **4.01 px** minimum clearance, including A. Intrinsic PNG alpha padding creates less than half a pixel of visible-margin asymmetry in landscape. Joystick targets remain 100 landscape, 116 short portrait, 130 tall portrait.

Portrait L/R artwork **44→32 px** tall, vertically centered within unchanged **44 px** hit targets. Widths and placement match. Start/Select and Settings remain in their existing positions. No input/action mapping, drawer/pinning or modal behavior changed. Existing 3x CSS/backing-pixel conversion and browser-reported safe-area handling remain.

## Render artifacts

Final real Compatibility-rendered screenshots and `geometry.json` are archived under `build/mobile-web/ui-v3.1/`:

- `explore-WxH.png`, `fishing-WxH.png`, `drawer-WxH.png`, `modal-WxH.png`: all eight requested sizes.
- `sea-continuity-*.png`: three water-facing camera positions.
- `world-640.png`/`world-960.png`: genuine horizontal projection comparison.
- `controls-scroll-*.png`/`controls-footer-*.png`: retained short-portrait fallback.

The test's final fishing captures now use balanced mobile A presses to reach a real cast and IN_WATER, rather than capturing only the AIM pose. Sea, shoreline, live HUD and controls were inspected. No striped filler polygon is visible in the corrected landscape renders. Physical Safari refresh acceptance remains necessary; native rendering does not prove thumb comfort/browser event behavior. Existing shortest portrait scrolling and constrained landscape edge-overlay tradeoffs remain.

## Executed QA

Executable: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`, with `--path` at this project. Wrappers redirect APPDATA/LOCALAPPDATA beneath ignored `build/mobile-web/root-repair/`; fixtures use disposable saves.

| Arguments | Result |
|---|---|
| `--headless --editor --import --quit` | Exit 0; no script compilation errors |
| `--rendering-method gl_compatibility --script res://scripts/qa/mobile_landscape_shell_qa.gd` | **455/455**: eight sizes, 40px header, centering, spacing, shorter artwork, input, drawer/modal, real cast, DEV cards |
| `--rendering-method gl_compatibility --script res://scripts/qa/mobile_surface_projection_qa.gd` | **334/334**: original-sea preservation, projection, actual 3x touch, scrolling and input exclusion |
| `--headless --script res://scripts/qa/mobile_portrait_harness_qa.gd` | **153/153** |
| `--headless --script res://scripts/qa/seaside_shell_layout_qa.gd` | **88/88** |
| `--headless res://actors/mobile/MobileWebParityQA.tscn` | **36/36**, native Web-capable fixture, not browser DOM execution |
| `--headless --script res://scripts/qa/fishing_camera_reconstruction_qa.gd -- --wide` | **124/124** |
| `--headless --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd` | **199/199** |
| `--headless --script res://scripts/qa/fishing_water_camera_qa.gd` | **16/16** |
| `--headless --script res://scripts/qa/runtime_lifecycle_qa.gd -- --mobile` | **1052/1052**, full fishing **22950/22950** |
| `--headless --script res://scripts/qa/session_contract_runner.gd` | PASS; full fishing **22950/22950**, Triple Triad **101/101**, zero orphans |
| `--headless --script res://scripts/qa/mobile_gameplay_parity_qa.gd` | **49/53**, same four existing synthetic fight-yaw foot-Y failures |
| `git diff --check` | PASS |

Lifecycle structural nodes stabilized at 2256, resources 2236, one service, zero orphans. The geometry adds a bounded scene-local visual population; it does not accumulate per travel cycle. Existing economy remains 22/24 with two H12 alerts. Existing GLES shader-cache write diagnostics remain unsuppressed. Reconstruction's intentional invalid-framing diagnostic is retained.

An initial continuity camera offset looked away from all Sea triangle centroids; that fixture failed its sample-count assertion. The test now explicitly aims its three diagnostic views at the actual Sea bounds and freezes scene motion while comparing frames. No preservation epsilon or assertion was weakened.

## Files changed in this pass

- `scripts/mobile/mobile_world_ground_extension.gd`
- `scripts/mobile/mobile_touch_controls.gd`
- `scripts/ui/seaside_shell_layout.gd`
- `scripts/ui/seaside_environment_strip.gd`
- `assets/models/shaders/mobile_inland_continuation.gdshader` and generated `.uid` (new)
- `scripts/qa/mobile_landscape_shell_qa.gd`
- `scripts/qa/mobile_surface_projection_qa.gd`
- `docs/qa/responsive_mobile_ui_v3_1.md` (new)
- Rebuilt `export/index.html` and `export/index.pck`

Removed v3's `assets/models/shaders/landscape_ground_extension.gdshader` and its `.uid`. Other pre-existing dirty files were retained. Original scene files, existing Beach/Sea shaders, camera, fishing mechanics, services and HTTPS code were not edited. Temporary rendering-audit scripts remain only in ignored build scratch output, outside production/export scope.

## Delivery

Rebuild command: `& .\tools\mobile\build_mobile_playtest.ps1`, using existing WSL/Linux Godot 4.7.2 and the Mobile Portrait Web Playtest preset. HTTPS stays running. PCK size/header validation is performed by the build helper. Refresh Safari after the successful build.

Final rebuild succeeded: `export/index.pck` **32,579,116 bytes**, internal `project.binary` **9,970 bytes**, valid **ECFG** header. `index.js` and `index.wasm` are byte-identical to the existing engine export. No server restart occurred.
