# Verified baseline inventory — FRESH6

This is a **static source inventory**, not a full audit and not a fresh Godot test/profiler run.

| Item | Verified snapshot value |
|---|---|
| Archive | `fishing_game_clean_candidate_FRESH6.zip` |
| SHA-256 | `d86254704232a533e42c7b45085f0b9c48b77c97229d9d863e8e5271a243dcd3` |
| ZIP integrity | PASS (`testzip() is None`) |
| Archive bytes | 75,869,791 |
| Uncompressed bytes | 121,669,972 |
| Files | 2,525 |
| `.gd` scripts | 530 |
| `.tscn` scenes | 152 |
| `.tres` resources | 477 |
| `.png` source images | 245 |
| `.gdshader` shaders | 7 |
| QA scripts directly under `scripts/qa` | 96 |
| Configured main scene UID | `uid://dqj6ysvar4jsa` |
| Resolved main scene | `actors/FishingTestScene_V2.tscn` |
| Separate desktop companion | `actors/desktop/DesktopCompanion.tscn` |
| Declared engine features | Godot 4.7 / Forward Plus; mobile_portrait GL Compatibility |
| User-reported installed Godot | 4.7.2 stable on Windows |
| Latest user-reported v7 integration QA | 182 passed, 0 failed; **not rerun here** |

## FRESH5 → FRESH6 archive comparison

- 29 added files; 11 modified existing files; 0 removed files (by path/name and CRC, not line-level Git history).
- Added environment QA scripts for v1–v7, game-weather service, presentation-policy script and QA documentation.
- Modified `scripts/fishing.gd`, environment-related services, rain VFX, relevant QA, and scenes.
- FRESH6 preserves the main gameplay scene/desktop companion entry-point split.

## Confirmed preflight observations (not full audit findings)

1. `project.godot` points to `uid://dqj6ysvar4jsa` → `actors/FishingTestScene_V2.tscn`. The desktop companion exists at `actors/desktop/DesktopCompanion.tscn`. Detailed launch-path/runtime behavior still needs verification.
2. `actors/FishingRainVFX.tscn` contains `weather_mode = 2`. `scripts/environment_fx/fishing_rain_world_vfx.gd` maps value 2 to **Rain Preview**, not Auto, while `scripts/world/playable_location_scene.gd` references the rain scene for world spawning. The v7 QA explicitly forces Auto mode. **Potential production inconsistency; verify it in Godot before classifying severity.** Do not reset approved art values without permission.
3. Source `.png.import` metadata is present. The generated `.godot/` import cache and `.git/` history are intentionally omitted, so fresh import/profile/history investigation requires a working Godot project/repository.
4. Generated `export/index.wasm` and `export/index.pck` are included (67.3 MiB uncompressed combined). They are not needed for source audit, and should be excluded from source asset budget tallies to avoid double counting.
5. No source edits were made during preflight.

## Largest GDScript files by source line count (triage only)

- `scripts/triple_triad/triple_triad_backend_qa.gd` — 4,588 lines
- `scripts/encounter.gd` — 3,597 lines
- `scripts/fishing_regression_harness.gd` — 2,998 lines
- `scripts/bait_V2.gd` — 2,259 lines
- `scripts/fishing.gd` — 2,173 lines
- `scripts/qa/fishing_save_recovery_interruption_qa.gd` — 1,892 lines
- `scripts/fishing_menu.gd` — 1,865 lines
- `scripts/triple_triad/triple_triad_deck_setup.gd` — 1,857 lines
- `scripts/camera_rig.gd` — 1,762 lines
- `scripts/dialogue/dialogue_system_qa.gd` — 1,565 lines
- `scripts/fish_shadow_actor.gd` — 1,550 lines
- `scripts/progression/economy_progression_simulator.gd` — 1,509 lines

A large file is **not** automatically bad architecture. Focus on responsibility, coupling, mutation paths and change-impact evidence.

## Known evidence limits

- No engine executed in this preflight; all QA results listed are user-reported past runs.
- No fresh runtime CPU/GPU frame times, draw calls, memory snapshots, import-cache footprint or load times.
- No Git history or working-tree diff in this source-only ZIP.
- Approved scene values are only those serialized in the uploaded snapshot; unsaved editor changes cannot be inferred.
