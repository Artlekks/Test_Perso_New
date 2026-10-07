# Beach collision diagnosis

Scene: `res://actors/FishingTestScene_V2.tscn`. Engine used: Godot 4.7.2 stable.
The working tree was clean before this investigation (Polish v1 was committed).
Physics bodies were identified before editing project source. A temporary,
save-free fixture instantiated the current scene, retained the real movers,
DepthFloor and WorldActorPresentation, and stripped unrelated gameplay scripts
before their `_ready()` callbacks. The Card Maker subtree retained its typed
dependencies. All positions below are world coordinates at startup.

## Identified faults

1. `World/FishingCardMakerNPC/BodyCollider`: default `sync_to_physics = true`
   on a child AnimatableBody3D suppresses ordinary inherited-transform updates
   to the physics server. Its Node3D transform and shape gizmo followed the
   parent, but the actual physics body remained at home. Before the fix,
   the visible root and node body reached `(1.088921, -0.124540, 0.349513)`
   while `PhysicsServer3D.body_get_state(..., BODY_STATE_TRANSFORM).origin`
   remained `(0.788921, -0.124540, 0.519513)`. This was one stale body, not a
   second duplicated body. The visual and collider shared the scene parent,
   but did not share the same physics-server transform.
2. `World/BeachCritter2/CollisionShape3D`: `_expand_actor_footprint()` exempted
   only the exact node name `BeachCritter`. The second instance was enlarged
   from sphere radius `0.075` to the NPC minimum `0.24` (3.2 times its intended
   radius). The first crab remained `0.075`. This created the oversized second
   obstruction. Neither gathering nor an imported beach collision generated it.

Both crabs also used synchronized bodies with render-tick, component-wise
position writes; synchronization could revert those writes. Before the fix,
both were still at their startup positions after a forced walking interval.
After the fix both axes advance and server/body/sprite positions agree.

## Body and shape inventory

Every path in this table has the full prefix
`/root/FishingTestScene_V2/World/`. A shape path is its listed body path plus
`/CollisionShape3D`. Positions distinguish body origin from shape center.
This inventory covers the gathering circuit and nearby bodies within
world X `[-4.1, 4.1]`; distant masters/registrar are outside the local area.

| Body path suffix | Type | Layer / mask | Body world position | Shape world position | Owning scene | Follows visible object? |
| --- | --- | --- | --- | --- | --- | --- |
| `FishingCardMakerNPC/BodyCollider` | AnimatableBody3D | 1 / 1 | (0.788921, -0.124540, 0.519513) | (0.788921, 0.125460, 0.519513) | `actors/FishingCardMakerNPC.tscn` | Before: node yes, physics no. After: both yes. Capsule runtime radius 0.24, height 0.52. |
| `BeachCritter2` | AnimatableBody3D | 1 / 1 | (1.613669, -0.055645, 0.344522) | (1.613669, 0.009355, 0.344522) | `actors/BeachFishingCritter.tscn` | Same root as sprite. Before radius 0.24; after 0.075 and movement synchronized. |
| `BeachCritter` | AnimatableBody3D | 1 / 1 | (-1.550000, -0.055645, 0.120000) | (-1.550000, 0.009355, 0.120000) | `actors/BeachFishingCritter.tscn` | Same root as sprite; radius 0.075; movement synchronized after fix. |
| `BeachCrafterNPC/BodyCollider` | StaticBody3D | 1 / 1 | (-0.800000, 0.070000, 0.653153) | (-0.800000, 0.061147, 0.653153) | `actors/BeachCrafterNPC.tscn` | Stationary, shares actor root. |
| `BeachMerchantNPC/BodyCollider` | StaticBody3D | 1 / 1 | (-1.948676, 0.062842, 0.609265) | (-1.948676, 0.312842, 0.609265) | `actors/BeachMerchantNPC.tscn` | Stationary, shares actor root. |
| `TripleTriadOpponentNPC/BodyCollider` | StaticBody3D | 1 / 1 | (2.021546, 0.074429, 0.033283) | (2.021546, 0.194429, 0.033283) | `actors/TripleTriadOpponentNPC.tscn` | Stationary, shares actor root. |
| `FishingMasterStillWaterNPC/BodyCollider` | StaticBody3D | 1 / 1 | (-2.468474, 0.070000, -0.076064) | (-2.468474, 0.320000, -0.076064) | `actors/FishingMasterStillWaterNPC.tscn` | Stationary, shares actor root. |
| `FishingMasterGyosilNPC/BodyCollider` | StaticBody3D | 1 / 1 | (-0.906299, 0.070000, -0.100000) | (-0.906299, 0.340000, -0.100000) | `actors/FishingMasterGyosilNPC.tscn` | Stationary, shares actor root. |
| `FishingMasterCurrentReaderNPC/BodyCollider` | StaticBody3D | 1 / 1 | (3.000000, 0.070000, -0.100000) | (3.000000, 0.320000, -0.100000) | `actors/FishingMasterCurrentReaderNPC.tscn` | Stationary, shares actor root. |
| `HarborLockbox/BodyCollider` | StaticBody3D | 1 / 1 | (3.620000, 0.070000, 0.500000) | (3.620000, 0.240000, 0.500000) | `actors/HarborLockbox.tscn` | Stationary, shares actor root. |
| `ShoreBlocker` | StaticBody3D | 1 / 1 | (0, 0.211945, -0.454296) | Same | `actors/FishingTestScene_V2.tscn` | Stationary shoreline, intentionally invisible. World box size approximately (6.037373, 0.8, 0.07), well north of the gathering props. |
| `DepthFloor` | StaticBody3D | 2048 / 0 | (0, 0, 0) | Same; vertices baked from beach/Bottom | `actors/FishingTestScene_V2.tscn`, shape created by `depth_floor_from_mesh.gd` | Static bottom collision; excluded from player's mask 1. One generated shape at startup. |

Player: `/root/FishingTestScene_V2/Player/CharacterBody3D`, CharacterBody3D,
layer/mask `1/1`, startup origin `(0,0,0)`, shape center `(0,0.223204,0)`,
owning scene `actors/ExplorationPlayer_V2.tscn`; sprite and capsule share root.
No other CharacterBody3D is instantiated in this local fixture. The imported
`beach.glb` supplies meshes, with no additional PhysicsBody3D in the inventory.
No collider body was duplicated by the presentation helper for either suspect.

## Interaction shapes inspected, unchanged

All gathering objects use the shared `actors/BeachGatheringNode3D.tscn` via
their `actors/gathering/*GatherNode.tscn` variant. Their full shape prefix is
`/root/FishingTestScene_V2/World/BeachGatheringCircuit/`; append the row name
and `/InteractionArea/CollisionShape3D`. The parent is Area3D, layer/mask
`0/3`, sphere radius `0.65`. Shapes follow their prop root. All prop root
world Y values are `0.006279432`; shape world Y is `0.256279432`.

| Gathering node | World X / Z (prop and shape) |
| --- | --- |
| Driftwood01 | -3.8 / 0.62 |
| Shell01 | -3.1 / 0.24 |
| Seaweed01 | -2.65 / 0.72 |
| Driftwood02 | -1.7 / 0.22 |
| IronScrap01 | -1.25 / 0.72 |
| SeaGlass01 | 0.25 / 0.68 |
| IronScrap02 | 0.85 / 0.22 |
| Shell02 | 1.4 / 0.68 |
| Driftwood03 | 2.7 / 0.24 |
| Seaweed02 | 3.45 / 0.65 |
| CoastalHerb01 | -2.2 / 0.48 |
| CoastalHerb02 | 2.05 / 0.43 |

NPC InteractionArea shapes also remain Area3D `0/3`; none blocks the player.
Card Maker interaction sphere radius `0.48`, startup center
`(0.788921,0.195460,0.519513)`, retains its root-relative offset during patrol.
`World/FishZone_V2/CollisionShape3D` and
`World/FishZone_V2/FishSwimBounds/BoundsShape3D` belong to Areas, not bodies.
The former center is `(0.021576,0,-0.740945)`; the latter center approximately
`(0.029772,-0.812916,-4.400637)`. FishSwimBounds is layer/mask `0/0`.
HarborRequestBoard has only an InteractionArea and no AnimatedSprite3D,
so the presentation helper does not create a fallback blocking body there.

## Minimal fix and verification

- Disable `sync_to_physics` in the Card Maker body so the scripted parent
  transform updates its actual physics transform. Keep the body at local zero.
- Tick Card Maker patrol/smoke/idle state and crab motion in `_physics_process`.
  Keep Card Maker visual depth sorting in `_process`.
- Disable crab synchronization so sequential X/Z writes are not reverted.
- Exempt `BeachFishingCritter` instances by type in `_expand_actor_footprint`.
  No shadow sizing, generation, positioning or sorting code changed.
- No gathering scene, world transform, collision layer/mask, or interaction
  Area was changed. `FishingTestScene_V2.tscn` itself is unchanged.

Commands actually run (PowerShell):

```powershell
$godotExe = 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe'
$qaOutput = 'C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c'
& $godotExe --headless --path . --log-file "$qaOutput/beach_collision_qa.log" --script res://scripts/qa/beach_collision_qa.gd | Out-String
& $godotExe --headless --path . --log-file "$qaOutput/world_interaction_qa.log" --script res://scripts/qa/world_interaction_qa.gd | Out-String
git diff --check
```

Results: beach collision QA **65 checks, 0 failures**; existing world interaction
QA **93/93 passed**; diff whitespace check passed. New QA tests the physics
server at all five patrol vertices, actual player-capsule collision with the
current Card Maker body, no old-home hit once outside the old footprint,
one Card Maker body, both crab shapes/movement, all twelve gathering nodes,
unchanged interaction radii/layers, and the bottom collision layer.
The temporary exploratory probe was removed. Rendered gameplay visual
inspection remains pending; the physics results are headless and use the
isolated current-scene fixture, not a full save-backed playthrough.
