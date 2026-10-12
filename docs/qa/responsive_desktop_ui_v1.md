# Responsive Desktop UI v1

Implemented 2026-10-11 directly against the clean working tree. Desktop presentation only; no camera, fishing, HUD, input mappings, save or economy scripts changed.

## Layout and ownership

The shared Seaside Shell now uses one environmental strip, one gameplay frame and one toolbar. There is no permanent equipment/menu/sidebar/keyboard panel. Inventory, Data/Journal and card access remain through existing game paths; Menu sends the existing J input. Settings and equipment editing invoke the existing menu controllers.

The environmental strip reads the existing location/environment/current services. Its order remains location, weather, day/time, wind, current, tide. In-game day/time and wind explicitly show N/A, rather than the computer clock. Narrow desktop uses two rows in that order. Mobile uses its unchanged existing geometry and indicators.

World shape is selected from the gameplay box remaining after header, margins and toolbar. A width/height ratio above 1.75 enters 960x480; below 1.60 returns to 640x480. The band retains the previous shape. Docked presentation selects 640x480. Fishing and collapsed windows lock their current resolution. A pending choice is recalculated through the normal exploration return, without restarting the scene. Both resolutions have a 480-pixel logical height. Scaling is uniform; existing KEEP_HEIGHT projection reveals extra world horizontally. The existing shared ground continuation supports the wider world. No camera distance, projection settings, transforms, controls or tracking parameters are edited.

Native AppBar ownership, title bar, maximization and restore remain in their existing controller. Dock height now reserves only the shared compact header, proportional world and toolbar. Float/Undock and Hide/Collapse are separate controls. Active and Passive remain independent of window state. The hidden legacy keyboard reminder remains available to its existing InputMap QA but has no permanent layout allocation.

Equipment uses the existing pinnable overlay, closed initially. Opening, pinning and closing do not change camera transforms or viewport size. Rod and lure/bait are read from the authoritative loadout/inventory. Editing opens the existing Equip page. Modal presentation hides the drawer.

## Rendered measurements

Native Godot 4.7.2 Compatibility rendering, real desktop scene, normal fishing entry and cast. Percentages use client area, excluding the native title bar. Before values are calculated from the previous committed layout at the same client dimensions; after values are measured from the rendered fixture.

| Configuration | Client | Header | Logical world | Displayed gameplay | Gameplay area before -> after | Toolbar |
| --- | --- | --- | --- | --- | --- | --- |
| Actual maximized | 2560x1494 | 40 | 960x480 (2:1) | 2548x1274 | 55.9% -> 84.9% | 2552x36 |
| Regular floating | 800x560 | 40 | 640x480 (4:3) | 621.33x466 | 10.1% -> 64.6% | 792x36 |
| Actual minimum left dock | 320x411 | 84 | 640x480 (4:3) | 308x231 | 4.2% -> 54.1% | 312x72 |

Screenshots inspected in exploration and IN_WATER for all three. Gameplay has no shell-induced crop/stretch. The regular view has approximately 89px side clearance because a 4:3 image cannot fill its wider box; the maximized view has approximately 132px below the toolbar. These are residual aspect-fit space, not permanent panels. Minimum dock has 12px bottom clearance. The existing black inland corner in the 4:3 beach scene remains visible; this pass did not alter world geometry there.

The player-relative HUD gap remains bar-height x 0.25 (14 logical pixels), approved gauge-origin separation 357, and artwork scales 0.35/0.36, tested in both desktop world resolutions. No layout-specific offsets were added.

Rendered captures and machine-readable measurements:

- `build/mobile-web/desktop-responsive/expanded-exploration.png`
- `build/mobile-web/desktop-responsive/expanded-fishing.png`
- `build/mobile-web/desktop-responsive/regular-exploration.png`
- `build/mobile-web/desktop-responsive/regular-fishing.png`
- `build/mobile-web/desktop-responsive/minimum-dock-exploration.png`
- `build/mobile-web/desktop-responsive/minimum-dock-fishing.png`
- `build/mobile-web/desktop-responsive/measurements.json`

## Verification actually run

Executable: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`.

From the project root, existing disposable wrappers ran the following commands with isolated user data and logs under `build/mobile-web/root-repair`. `run.py` supplies `--headless --path <project>`; `render_run.py` supplies `--rendering-method gl_compatibility --path <project>`. Native AppBar fixtures were run outside the sandbox with approval.

| Command suffix | Result |
| --- | --- |
| `--editor --import --quit` | Exit 0 |
| `--script res://scripts/qa/responsive_desktop_ui_qa.gd` (rendered) | 67/67 |
| `--script res://scripts/qa/desktop_companion_docking_qa.gd` (rendered/native) | 590/590, including preserved shape during collapse |
| `--script res://scripts/qa/desktop_floating_qa.gd` (rendered/native) | 14/14 |
| `--script res://scripts/qa/seaside_shell_layout_qa.gd` | 88/88; existing menu-page coverage retained |
| `--script res://scripts/qa/fishing_camera_hud_stability_qa.gd -- --desktop` (rendered) | 45/45 |
| `--script res://scripts/qa/fishing_camera_reconstruction_qa.gd` | 124/124 |
| `--script res://scripts/qa/fishing_camera_reconstruction_qa.gd -- --wide` | 124/124 |
| `--script res://scripts/qa/empty_lure_retrieval_qa.gd` | 286/286 |
| `--script res://scripts/qa/passive_fishing_qa.gd` | 95/95 |
| `--script res://scripts/qa/runtime_lifecycle_qa.gd` | 1832/1832 |
| `--script res://scripts/qa/runtime_lifecycle_qa.gd -- --mobile` | 1052/1052 |
| `--script res://scripts/qa/mobile_portrait_harness_qa.gd` | 153/153 |
| `--script res://scripts/qa/mobile_landscape_shell_qa.gd` (headless and rendered) | 455/455 each |
| `--script res://scripts/qa/mobile_gameplay_parity_qa.gd` | 49/53; same four baseline normalized foot-Y failures |
| `--script res://scripts/qa/session_contract_runner.gd` | Full fishing 22950/22950; contract runner PASS, zero orphan nodes |
| `git diff --check` | PASS |

The new fixture proves area/aspect selection, hysteresis, actual minimum AppBar registration, drawer behavior, explicit unavailable information, real water entry, player-relative HUD geometry, fishing resize/session persistence, unchanged camera transform during frozen-target resizing, normal fishing exit and deferred world-shape application. It does not substitute for physical gameplay feel.

The initial sandboxed AppBar attempt failed because its helper exited; it was not counted as a pass. Native reruns above passed. Existing GLES shader-cache write diagnostics remain in rendered logs. Existing four mobile foot-Y failures were neither suppressed nor adjusted. Existing H12 economy balance alerts remain outside this pass.

Physical Windows title-bar dragging, resize gestures and Snap should still be checked by the designer; automated native QA validates programmatic geometry and styles, not human gestures. No Safari acceptance is claimed. Mobile rendered parity passes, and no mobile layout/input behavior changed, so Web was not rebuilt and HTTPS was not restarted.

## Complete changed-file inventory

- `scripts/desktop/desktop_companion.gd`
- `scripts/ui/seaside_shell_layout.gd`
- `scripts/ui/seaside_shell_view.gd`
- `scripts/ui/seaside_environment_strip.gd`
- `scripts/qa/seaside_shell_layout_qa.gd`
- `scripts/qa/desktop_companion_docking_qa.gd`
- `scripts/qa/responsive_desktop_ui_qa.gd` (new)
- `scripts/qa/responsive_desktop_ui_qa.gd.uid` (new, generated by Godot import)
- `docs/qa/responsive_desktop_ui_v1.md` (new)
