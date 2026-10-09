# Grounding Failure Root-Cause Audit v1

Date: 2026-10-09. Godot 4.7.2 (`ed1daf0bf`).

All 12 known failures were reproduced and individually inspected. They are real
runtime/architecture defects in gathering interaction-volume placement, with a
common cause. None was a stale expectation, bad baseline assumption, or an
intentional exception. No assertion was removed, relaxed or rebaselined.

## Evidence and root cause

The original grounding suite reproduced **1048/1060**, with exactly the 12
`physics world position unchanged` failures below. A separately captured live
physics inventory confirmed every affected shape was at Y **0.25**, while the
preserved baseline requires Y **0.256279438734055**. X/Z, basis, enabled state,
collision layer and mask were unchanged.

Before normalization, each gathering root had local Y `0.04` beneath a circuit
instance at Y `-0.033720568`. Its net world height was `0.0062794313`. The sphere
was a further `0.25` above that root.

Commit `d5aaec1` normalized gathering roots/circuit to Y=0 and explicitly
compensated each InteractionArea by `0.0062794313`, preserving its physical
volume. Commit `7c8e4b8` subsequently removed all 12 inherited-node compensation
overrides from `actors/FishingTestScene_V2.tscn` without relocating their values
into the shared base. The visible grounding remained normalized, but the
physical interaction volumes moved down. This violates the documented
physics-preservation contract; it is not a reason to change the baseline.

## Every original failure

Owning world scene for every row: `actors/FishingTestScene_V2.tscn`.
For every row below the exact assertion is the listed path followed by
` physics world position unchanged`. Classification: **real runtime/architecture
defect**. Each row lost its Area compensation, lowering its sensor from the
required Y=0.256279438734055 to Y=0.25. Each is repaired by inheriting the shared
physics-only Area offset; none has an assertion correction.

| # | Exact assertion path | Authored actor resource | Individual diagnosis / fix |
|---|---|---|---|
| 1 | `World/BeachGatheringCircuit/Driftwood01/InteractionArea/CollisionShape3D` | `actors/gathering/DriftwoodGatherNode.tscn` | Removed Driftwood01 Area override; shared compensation restored. |
| 2 | `World/BeachGatheringCircuit/Shell01/InteractionArea/CollisionShape3D` | `actors/gathering/ShellGatherNode.tscn` | Removed Shell01 Area override; shared compensation restored. |
| 3 | `World/BeachGatheringCircuit/Seaweed01/InteractionArea/CollisionShape3D` | `actors/gathering/SeaweedGatherNode.tscn` | Removed Seaweed01 Area override; shared compensation restored. |
| 4 | `World/BeachGatheringCircuit/Driftwood02/InteractionArea/CollisionShape3D` | `actors/gathering/DriftwoodGatherNode.tscn` | Removed Driftwood02 Area override; shared compensation restored. |
| 5 | `World/BeachGatheringCircuit/IronScrap01/InteractionArea/CollisionShape3D` | `actors/gathering/IronScrapGatherNode.tscn` | Removed IronScrap01 Area override; shared compensation restored. |
| 6 | `World/BeachGatheringCircuit/SeaGlass01/InteractionArea/CollisionShape3D` | `actors/gathering/SeaGlassGatherNode.tscn` | Removed SeaGlass01 Area override; shared compensation restored. |
| 7 | `World/BeachGatheringCircuit/IronScrap02/InteractionArea/CollisionShape3D` | `actors/gathering/IronScrapGatherNode.tscn` | Removed IronScrap02 Area override; shared compensation restored. |
| 8 | `World/BeachGatheringCircuit/Shell02/InteractionArea/CollisionShape3D` | `actors/gathering/ShellGatherNode.tscn` | Removed Shell02 Area override; shared compensation restored. |
| 9 | `World/BeachGatheringCircuit/Driftwood03/InteractionArea/CollisionShape3D` | `actors/gathering/DriftwoodGatherNode.tscn` | Removed Driftwood03 Area override; shared compensation restored. |
| 10 | `World/BeachGatheringCircuit/Seaweed02/InteractionArea/CollisionShape3D` | `actors/gathering/SeaweedGatherNode.tscn` | Removed Seaweed02 Area override; shared compensation restored. |
| 11 | `World/BeachGatheringCircuit/CoastalHerb01/InteractionArea/CollisionShape3D` | `actors/gathering/CoastalHerbGatherNode.tscn` | Removed CoastalHerb01 Area override; shared compensation restored. |
| 12 | `World/BeachGatheringCircuit/CoastalHerb02/InteractionArea/CollisionShape3D` | `actors/gathering/CoastalHerbGatherNode.tscn` | Removed CoastalHerb02 Area override; shared compensation restored. |

## Repair and regression protection

`actors/BeachGatheringNode3D.tscn` now owns
`InteractionArea.position = Vector3(0, 0.0062794313, 0)`.
All six derived gathering resources and all 12 circuit instances inherit it.
The sphere's existing local Y=0.25 and radius=0.65 remain intact, as do Area
layer=0/mask=3, monitoring, and gathering behavior. No blocking body was added.

This is a physical sensor-origin compensation, not a visual offset. ActorRoot
remains the physical ground/feet origin at Y=0. Presentation profiles, sprite
transforms, shared shadow families, and destination scenes are untouched.

`test_gathering_sensor()` in `scripts/qa/world_grounding_standard_qa.gd` adds two
actual physics checks per affected item. A scriptless CharacterBody3D probe
with a 0.001m sphere and player-compatible collision layer is placed just
inside the historical upper boundary, then outside it. The actual Area must
detect the first and reject the second after physics frames settle. Expected
centers come from the unchanged authored physics baseline, not the current
scene's possibly incorrect position. The probe has no player group and cannot
trigger gathering or save writes.

A controlled mutation restored the defective zero Area offset temporarily:
the unchanged 12 position checks **and** all 12 new inside-boundary checks
failed, producing **1060/1084**, exit 1. The repaired file was restored in a
`finally` block. With the repair, the same suite passed **1084/1084**, exit 0.
This demonstrates a real physics-volume difference, not merely a snapshot
disagreement. The unchanged outside-boundary tests also passed.

## Commands actually run and results

The PowerShell runs used `Start-Process -WindowStyle Hidden -Wait -PassThru`
with this executable:

```powershell
$godot = 'C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe'
```

Commands below show the exact Godot arguments. Each also used `--log-file`
under `build/mobile-web/grounding-audit-*.log`; rendered captures and JSON
inventories are in the same ignored build directory.

| Command | Result |
|---|---|
| `Godot --headless --path . --script scripts/qa/world_grounding_standard_qa.gd` (original reproduction) | 1048/1060, exit 1; exactly 12 original failures. |
| Same command after adding overlap checks, with defective offset deliberately reproduced | 1060/1084, exit 1; expected mutation failure. |
| Same command with final repair | **1084/1084**, exit 0. |
| `Godot --path . --rendering-method gl_compatibility --script scripts/qa/world_grounding_standard_qa.gd -- --rendered --capture-dir=res://build/mobile-web/grounding-audit-captures` | **1088/1088**, exit 0; four rendered captures saved and visually inspected. |
| `Godot --headless --path . --script scripts/qa/world_presentation_tuning_qa.gd -- --measurements=res://build/mobile-web/grounding-audit-presentation.json` | **265/265**, exit 0. |
| `Godot --headless --path . --script scripts/qa/npc_catalog_qa.gd` | **2589/2589**, exit 0. |
| `Godot --headless --path . --script scripts/qa/beach_collision_qa.gd` | **65 checks, 0 failures**, exit 0. |
| `Godot --headless --path . --script scripts/qa/world_actor_collision_qa.gd` | **96/96**, exit 0; maximum passive player displacement **0.0m**, epsilon 0.00001m. |
| `Godot --headless --path . --script scripts/qa/world_interaction_qa.gd` | **93/93**, exit 0. |
| `Godot --headless --path . --script scripts/qa/world_location_access_qa.gd` | **586 checks, 0 failures**, exit 0. |
| `Godot --headless --path . --script scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions` | Camera **168/168**, full fishing **22950/22950**, exit 0. Includes Fight **24/24**, Presentation **10/10**, Bite Timing **14/14**, System Stability **27/27**, Fresh Save **55/55**. |
| `Godot --headless --path . --script scripts/qa/world_grounding_inventory.gd -- --output=res://build/mobile-web/grounding-audit-live-after.json` | Separate repaired runtime physics inventory captured, exit 0. |
| `git diff --check` | Passed, no whitespace errors. |

The completed regression runs had no `ERROR:` or `SCRIPT ERROR:` output.
Existing QA-only warnings about reading source PNGs as images and expected
Triple Triad backend-not-ready defensive checks remain visible. Dedicated
economy balance targets were not modified or reclassified in this pass.

Rendered evidence is native Godot Compatibility execution at four scripted
camera angles, with the stationary merchant shadow transform checked at every
angle. It is not a claim that every animation of every actor was manually
reviewed on an iPhone. All requested suites and all 12 individual failures were
inspected; physical Safari acceptance was not performed in this audit.

## Web rebuild and changed files

Because a runtime scene changed, ran:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1
```

Linux/WSL export completed successfully with the existing preset and workflow.
Validated `export/index.pck`: **31,973,136 bytes**; internal `project.binary`:
**9,944 bytes**, valid **ECFG** header. `export/index.html` is ready for Safari
refresh. HTTPS was not started or restarted. The tracked generated artifacts
`export/index.html` and `export/index.pck` changed during this rebuild;
`index.js` and `index.wasm` remained byte-identical.

Source files changed:

- `actors/BeachGatheringNode3D.tscn`: shared physics-only sensor-origin repair.
- `scripts/qa/world_grounding_standard_qa.gd`: 24 actual overlap assertions.
- `docs/mobile/grounding_failure_root_cause_audit_v1.md`: this individual audit.

Generated files changed: `export/index.html`, `export/index.pck`.

No economy, UI, fishing presentation, camera, shadow/profile, or destination
scene source files changed.
