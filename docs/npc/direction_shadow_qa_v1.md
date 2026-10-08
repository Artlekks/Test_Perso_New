# Direction and shadow workflow verification

All commands ran from the current project using `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`, launched with `Start-Process -WindowStyle Hidden -Wait -PassThru`. Each used a `--log-file build/direction-shadow-release-<suite>.log` argument. Gameplay fixtures use isolated userdata; no normal save was modified.

| Arguments | Actual result |
|---|---|
| `--path . --script scripts/qa/npc_direction_shadow_qa.gd -- --rendered` | 1839/1839, exit 0; all 36 catalogue actors and five playable worlds; actual 360-degree camera rotations, shadow mutation/restoration and category independence |
| `--headless --path . --script scripts/qa/npc_catalog_qa.gd` | 2589/2589, exit 0 |
| `--headless --path . --script scripts/qa/world_presentation_tuning_qa.gd` | 265/265, exit 0; includes comparison against existing player direction behavior |
| `--headless --path . --script scripts/qa/world_grounding_standard_qa.gd` | 1048/1060, exit 1; same 12 known gathering InteractionArea shape baseline mismatches, no additional failures |
| `--headless --path . --script scripts/qa/world_interaction_qa.gd` | 93/93, exit 0 |
| `--headless --path . --script scripts/qa/world_actor_collision_qa.gd` | 96/96, exit 0; maximum passive player displacement 0.0, epsilon 0.00001 |
| `--headless --path . --script scripts/qa/world_location_access_qa.gd` | 586/586, exit 0 |
| `--headless --path . --script scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions` | camera 120/120, full fishing 22950/22950; exit 0; campaign loop 14/14, fresh save 55/55, fight 24/24, presentation 10/10, stability 27/27 |

`python -m py_compile tools/npc/build_npc_catalog.py`: passed. `git diff --check`: passed, with existing CRLF normalization advisories. Economy target findings remain 22/24; no balance values were changed.

Rendered Godot runs retained the existing native Vulkan `shader_rd.cpp:696 f.is_null()` cache-write errors (five in the final rendered log). The Triple Triad precomposition guard warning remains an expected defensive QA probe. These diagnostics were not suppressed. An intermediate new-QA type-inference parse error was corrected; the final script loads and completes successfully.

Rendered evidence is in `build/direction-shadow-captures/`. Close-ups revealed that Rod Angler pose_001's old automatic stance anchor selected the low dangling lure at x=59 rather than the body feet. The reusable profile/source sidecar now uses body stance x=19.5 and bottom padding=3. No actor, collider or shadow transform changed. A magenta guide-edge bleed remains visible on that alternate view. Atlas clipping/UV inset attempts did not remove it in rendered tests and were reverted; no source PNG or atlas-region correction is claimed. This cosmetic source/rendering cleanup remains outstanding.

Automatic approval review rejected a combined broad metadata update as risking three functional NPC profiles. Read-only searches proved `available_directions` and `directional_mode` are descriptive fields only, with no runtime consumers. Their source strips were inspected, and the final narrow change only replaced `one view` with the actual `SE` metadata label; default poses, animation prefixes and action controllers remained unchanged. Rendered and regression verification then passed. No requested work remains approval-blocked.

The validated Linux/WSL build command ran successfully:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1
```

Final PCK: 31,955,008 bytes; project.binary: 9,944 bytes with ECFG header. Existing HTTPS server was not restarted. Physical iPhone acceptance is still required: rotate around placed NPCs through full turns, inspect front/side/back selection, mirrored props, stable feet/shadows and Card Maker walking/stopping. Open Still Water's GroundPresentation profile and expand its shared family Resource; changing standard width/depth should propagate while player remains independent. No final cosmetic sizing is claimed.
