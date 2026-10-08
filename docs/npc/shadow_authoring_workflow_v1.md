# Shared shadow authoring workflow

For FishingMasterStillWaterNPC, select GroundPresentation, expand Profile (`data/presentation/still_water.tres`), then expand **Shared ground shadow / Shadow Family Resource**. It references `data/presentation/shadows/humanoid_standard.tres`. Edit width/depth/opacity there, or open that resource directly in the FileSystem dock. Every profile referencing the category updates in the editor/runtime presentation loop. Do not Make Unique on the family resource to tune a whole category.

The catalogue actor equivalent is its reusable NPC visual profile under `data/npc/profiles/`. An unusual actor can adjust Shadow Scale Multiplier there (default 1.0). Functional NPCs use their reusable grounding profiles under `data/presentation/`. Never add a multiplier, sprite compensation or shadow transform override to a Beach/Lake/River scene instance.

Why nested mesh edits appeared ineffective: WorldBlobShadow.tscn provides a standalone mesh default; on readiness the renderer duplicates its PlaneMesh/material; GroundPresentation then assigns category width/depth multiplied by the profile scale every frame. Those values overwrite nested width/depth and mesh size. The authoritative chain is shared category Resource -> reusable profile multiplier -> renderer fields/private mesh. Renderer style fields are now stored/internal rather than exposed as competing tuning controls. A legacy family string remains hidden for compatibility; the visible Resource reference is authoritative.

No family sizes/opacities were cosmetically tuned. No destination scene transforms changed. No F10 page was added; the inspector Resource link is the single low-risk tuning surface.

| Resource under data/presentation/shadows/ | Width | Depth | Opacity | Ground offset |
|---|---:|---:|---:|---:|
| critter.tres | 0.1 | 0.1 | 0.6 | 0.006 |
| ground_prop.tres | 0.1 | 0.1 | 0.4 | 0.006 |
| humanoid_large.tres | 0.28 | 0.28 | 0.65 | 0.006 |
| humanoid_small.tres | 0.18 | 0.18 | 0.65 | 0.006 |
| humanoid_standard.tres | 0.22 | 0.22 | 0.65 | 0.006 |
| item.tres | 0.07 | 0.07 | 0.35 | 0.004 |
| player.tres | 0.18 | 0.18 | 0.65 | 0.006 |

All 36 catalogue NPC multipliers remain 1.0; no current humanoid gameplay NPC has a scale exception. Existing ground-item/prop exceptions were preserved: coastalherb/driftwood/ironscrap/seaweed 1.14285714; seaglass/shell 0.71428571; harborlockbox 1.6; regionalchampionshipregistrar 1.8. Player is assigned the independent player family.

Focused QA changes standard-family width/depth/opacity in memory, checks every catalogue assignment and every placed world actor, verifies independent player/large/small/critter/prop/item categories against their original values, tests a temporary 1.5x reusable profile multiplier, then restores all mutated resources. Nothing is saved to disk during these tests. Eight camera rotations verify world-aligned root-centred shadows, including the moving Card Maker.
