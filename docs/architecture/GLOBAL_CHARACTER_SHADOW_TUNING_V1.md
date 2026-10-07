# Global Character Shadow Tuning v1

Presentation-only tuning of the existing ActorRoot → ShadowAnchor →
WorldBlobShadow architecture. No legacy nodes, art, per-direction tables,
animation offsets or gameplay changes were introduced. Card Maker smoke remains
disabled. The original shadow-system migration is still uncommitted in this
working tree; this tuning pass preserves those existing changes.

## Final values

| Class | Width | Depth | Opacity | Ground offset | Authored anchor offset |
| --- | --- | --- | --- | --- | --- |
| Humanoid NPCs: Merchant, Crafter, Card Maker, Triple Triad opponent, all Fishing Masters/Gyosil | 0.26 | 0.30 | 0.65 | 0.006 | (0,0,0) |
| Player | 0.24 | 0.28 | 0.65 | 0.006 | (0,0,0) |
| Both crabs | 0.14 | 0.16 | 0.65 | 0.006 | (0,0,0) |

The humanoid shared default was 0.40 × 0.18, player 0.36 × 0.17 and crabs
0.22 × 0.10. Opacity was 0.38 for every class; it is now 0.65, approximately
71% higher alpha. Ground lift and render ordering remain unchanged.

Inspection of Shadow.png found a 30 × 24 pixel canvas, occupied alpha bounds
(2,4)-(28,20), and alpha centroid exactly (15,12). The mask is already centered
but intrinsically oval. Narrowing the plane and giving it slightly greater
depth compensates for the mask: humanoid occupied world bounds become about
0.225 × 0.200, versus the old 0.347 × 0.120. This is a shorter, less elongated
contact footprint. It is a starting tuning target, not proof of rendered fit.

No actor/base scene received a nonzero local offset. All keep the physical root
center rather than introducing an unverified stance displacement. Optional
Inspector tuning of `ShadowAnchor.position` is now facing-invariant: the
component treats that authored local vector as a fixed world-aligned offset
from the actor's root translation. It does not multiply it by actor facing or
scale, so changing facing cannot orbit the shadow around the character.

## Inspector tuning

- Select `Actor/ShadowAnchor/WorldBlobShadow`: tweak **width, depth, opacity,
  ground_offset**. The shared scene controls humanoid defaults; player/crab
  scenes override only dimensions. Mesh/material settings remain instance-local.
- Select `Actor/ShadowAnchor`: tweak **Transform → Position X/Z** for a small
  stance correction if rendered inspection warrants one. Leave Y at zero and
  use **ground_offset** for vertical lift. The offset is fixed in world axes.
- Never adjust AnimatedSprite3D or add direction-specific offsets to tune shadows.

## Files changed by this tuning pass

1. `scripts/world/world_blob_shadow.gd` — compact/darker defaults and
   facing-invariant optional stance offset.
2. `actors/WorldBlobShadow.tscn` — matching plane/material defaults.
3. `actors/ExplorationPlayer_V2.tscn` — player dimensions only.
4. `actors/BeachFishingCritter.tscn` — shared crab dimensions only.
5. `scripts/qa/world_character_shadow_qa.gd` — final class values, opacity/lift
   checks and eight-direction nonzero-offset regression coverage.
6. `docs/architecture/GLOBAL_CHARACTER_SHADOW_V1.md` — current values and offset
   semantics updated; original migration QA remains historical.
7. `docs/architecture/GLOBAL_CHARACTER_SHADOW_TUNING_V1.md` — this report.

Existing modifications from the preceding architecture pass are not additional
tuning edits. Its uid files were present when this tuning pass started.

## Verification

Godot 4.7.2 stable, save-free headless fixtures:

```powershell
$godotExe = 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe'
$qaOutput = 'C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c'
& $godotExe --headless --path . --log-file "$qaOutput/shadow_tuning_qa.log" --script res://scripts/qa/world_character_shadow_qa.gd | Out-String
& $godotExe --headless --path . --log-file "$qaOutput/shadow_tuning_collision_qa.log" --script res://scripts/qa/beach_collision_qa.gd | Out-String
& $godotExe --headless --path . --log-file "$qaOutput/shadow_tuning_interaction_qa.log" --script res://scripts/qa/world_interaction_qa.gd | Out-String
git diff --check
```

Final results: shadow QA **905 checks, 0 failures**, collision QA **65 checks,
0 failures**, interaction QA **93/93 passed**, whitespace check passed.
Shadow QA includes all eight player directions, camera rotation, synthetic
sprite flips/frame offsets, all Card Maker patrol legs/stops, tree pause,
one shadow per character, and optional nonzero stance offsets that cannot rotate
with facing. No shadow correctness claim is based on rendered pixels here.

Rendered visual inspection remains pending. Run FishingTestScene_V2 in Godot
and inspect NPC belly/feet placement, compactness and darkness; Ryu in all eight
directions; both crab shadows; Card Maker walking/turning/stopping/dialogue; and
camera rotation/overlap for ground flicker or shadows drawing over bodies.
Use the Inspector controls above to refine subjective fit after that inspection.
