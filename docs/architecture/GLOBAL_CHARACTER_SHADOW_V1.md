# Global Character Shadow System v1

## Inspection and scope

The starting implementation had 19 manually transformed `ShadowSprite3D`
nodes, plus a player-instance transform override in `FishingTestScene_V2`.
`WorldActorPresentation` hid these nodes and created additional world-sibling
meshes from `WorldBlobShadow.tscn`. That scene used `blob_shadow_soft.png`.
The runtime helper owned their size, placement, update list and cleanup.
Its crab-size override matched only `BeachCritter`, missing the second crab.

Inspected player, Merchant, Crafter, Card Maker, Triple Triad opponent, all
14 Fishing Master character scenes, `FishingMasterLessonNPCBase`,
`FishingRewardClaimNPCBase`, and the Crafter/Card Maker request sources.
The bases and request sources do not implement shadows. Their characters
receive presentation through their authored scenes; no interaction/base
scripts needed modification. Gyosil is the reward-claim-base character.
Lockbox, request board and championship registrar are mesh props, not
characters, and remain unchanged. Fishing HUD and fish shadows are separate
systems and remain unchanged.

## Shared architecture

```text
Actor root (physical root/collider origin)
  ShadowAnchor (Node3D, identity local transform)
    WorldBlobShadow (shared scene, MeshInstance3D + reusable @tool script)
  AnimatedSprite3D
  existing collider / interaction nodes
```

The component follows the actor's world/root position in X/Z, plus the authored
`ShadowAnchor.position` as one fixed world-aligned stance offset. This keeps
optional nonzero offsets from rotating around the root when facing changes.
The anchor is a direct child at the physical actor root, never an animation-frame foot marker.
The shadow is top-level **for transforms only** and retains normal parent
ownership/lifetime. Each update assigns identity world basis and projects Y
to the ground reference plus its ground offset. Actor yaw/scale, camera yaw,
billboards, flips, sprite offsets and animation frame changes cannot modify
its orientation or physical center.

`WorldActorPresentation` assigns `World/beach/Beach` as the horizontal ground
reference to each authored component. It no longer creates/hides shadows or
maintains a separate shadow update/cleanup list. Existing sprite-priority and
collision-footprint behavior are preserved. A freed-reference check now runs
before casting sprite-sort entries, avoiding an error when a character is freed.

Without a ground reference, a standalone actor scene uses its anchor's world Y.
For another flat level, supply that level's ground reference. This v1 is a
horizontal-plane shadow, not a terrain-raycast system. No physics queries or
gameplay collision changes are needed for the component.

The reusable component exports these Inspector controls:

| Control | Default | Meaning |
| --- | --- | --- |
| width | 0.26 | Plane width in world units |
| depth | 0.30 | Plane depth in world units |
| opacity | 0.65 | Black shadow alpha |
| ground_offset | 0.006 | World-space lift above the ground plane |

Per-instance mesh/material copies prevent settings from leaking between actors.
The existing `assets/sprites/shared/Shadow.png` supplies the white ellipse mask;
the material tints it black. No art was generated or edited. The plane is
unshaded, transparent, depth-tested, does not write depth or cast real shadows,
and has render priority **-120**, below gathering sprites (-110) and character
sprites (-90 through 90). It stays flat and above the beach to avoid z-fighting.
The component updates after actor presentation, including while dialogue/menu
pause is active, and is freed automatically with its owning actor.

## Migrated actors and overrides

Twenty authored character scenes produce **21 characters/shadows** in the
current level: player, Merchant, Crafter, Card Maker, Triple Triad opponent,
14 Fishing Masters and two instances of the crab scene.

- Player: width **0.24**, depth **0.28**.
- Both crabs: width **0.14**, depth **0.16**, inherited from their shared scene.
- All humanoid NPCs including Card Maker: default **0.26 x 0.30**.
- All use default opacity **0.65** and ground offset **0.006**.

These values reflect Global Character Shadow Tuning v1. See
`GLOBAL_CHARACTER_SHADOW_TUNING_V1.md` for that pass's file list and QA results.

No actor uses a custom shadow transform. Card Maker smoke remains disabled.
His body synchronization and patrol behavior from the previous collider fix
are unchanged. Shadow movement reads his actual root, including stopping,
turning and paused interaction states; it does not read sprite frame positions.

Removed 19 legacy Sprite3D nodes and their private material/texture references,
the player-level instance override, and the controller's runtime sibling-shadow
creation/hiding/scale/update/cleanup implementation. `WorldBlobShadow.tscn`
was reused and upgraded, not replaced with another scene. The now-unused
`blob_shadow_soft.png` asset remains in the project; no asset files were deleted.

## Complete changed-file manifest

Modified character scenes:

1. `actors/ExplorationPlayer_V2.tscn`
2. `actors/BeachMerchantNPC.tscn`
3. `actors/BeachCrafterNPC.tscn`
4. `actors/FishingCardMakerNPC.tscn`
5. `actors/TripleTriadOpponentNPC.tscn`
6. `actors/FishingMasterStillWaterNPC.tscn`
7. `actors/FishingMasterCurrentReaderNPC.tscn`
8. `actors/FishingMasterDepthReaderNPC.tscn`
9. `actors/FishingMasterStructureHunterNPC.tscn`
10. `actors/FishingMasterLineFighterNPC.tscn`
11. `actors/FishingMasterDeepwaterVeteranNPC.tscn`
12. `actors/FishingMasterSurfaceAnglerNPC.tscn`
13. `actors/FishingMasterLandingGuideNPC.tscn`
14. `actors/FishingMasterWeatherWatcherNPC.tscn`
15. `actors/FishingMasterTideReaderNPC.tscn`
16. `actors/FishingMasterSignReaderNPC.tscn`
17. `actors/FishingMasterNatureGuideNPC.tscn`
18. `actors/FishingMasterDriftAnglerNPC.tscn`
19. `actors/FishingMasterGyosilNPC.tscn`
20. `actors/BeachFishingCritter.tscn`

Other modified files:

21. `actors/FishingTestScene_V2.tscn`
22. `actors/WorldBlobShadow.tscn`
23. `scripts/world_actor_presentation.gd`

New files:

24. `scripts/world/world_blob_shadow.gd`
25. `scripts/qa/world_character_shadow_qa.gd`
26. `docs/architecture/GLOBAL_CHARACTER_SHADOW_V1.md`

## QA actually run

Godot **4.7.2 stable** was run headless. These are transform/structural/physics
checks; no rendered gameplay screenshot or human visual inspection was made.
Fixtures disable unrelated gameplay scripts before readiness, avoiding player
save mutation; the shadow QA retains the real Card Maker/crab mover scripts.

```powershell
$godotExe = 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe'
$qaOutput = 'C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c'
& $godotExe --headless --path . --log-file "$qaOutput/world_character_shadow_qa.log" --script res://scripts/qa/world_character_shadow_qa.gd | Out-String
& $godotExe --headless --path . --log-file "$qaOutput/shadow_collision_regression.log" --script res://scripts/qa/beach_collision_qa.gd | Out-String
& $godotExe --headless --path . --log-file "$qaOutput/shadow_interaction_regression.log" --script res://scripts/qa/world_interaction_qa.gd | Out-String
git diff --check
```

Final results:

- World Character Shadow QA: **756 checks, 0 failures**, no runtime errors.
- Existing beach collision QA: **65 checks, 0 failures**.
- Existing world interaction QA: **93/93 passed**.
- `git diff --check`: passed.
- Baseline comparison: all **21 migrated/level scenes** retain identical
  non-shadow node properties and subresources, including actor transforms,
  collision, animations and interaction Areas. Controller collision-footprint
  implementation matches HEAD exactly. The comparison script was run with the
  bundled Python runtime against `git show HEAD:<file>`.
- Search: no `ShadowSprite3D` implementation/override remains in actor scenes,
  and no old controller blob-spawn/update code remains. The QA intentionally
  contains the legacy name to detect regressions.

New QA covers exactly one shadow per character, physical-root anchoring,
absence of animated-sprite ancestry/legacy nodes, world-flat orientation,
ground projection, material ordering/depth settings, shared texture, all eight
player facing animations combined with actor/camera rotation, sprite flips
and offsets, every Card Maker patrol leg, stops/turns/tree pause, per-instance
Inspector controls, idempotent controller setup and actor/shadow cleanup.
The paused test checks presentation stability; it does not exercise a live
save-backed dialogue transaction.

## Exact remaining visual checks in Godot

Open and run `actors/FishingTestScene_V2.tscn`:

1. Move Ryu in **S, SE, E, NE, N, NW, W, SW**, then stop in each direction.
   The shadow center must stay at the same collider/root foot location without
   direction-specific X/Z shifts or rotation.
2. Rotate the exploration camera through a full turn while Ryu is stopped,
   then while moving. The blob must stay flat and fixed in world orientation;
   camera projection may change its apparent shape, never its physical center.
3. Observe Card Maker through a full patrol loop, each stop and turn. Enter his
   radius without talking, then press K to start dialogue, dismiss it, and open
   his workshop. Shadow must follow his current root and remain still when he
   stops. Confirm no old-home/second shadow appears and smoke stays disabled.
4. Inspect Merchant, Crafter, Triple Triad opponent, every Fishing Master and
   both crabs. Check one centered shadow each; both crabs use the same small size.
5. Walk Ryu in front of and behind NPCs and overlap their shadows near Sea Glass
   and other gathering props. Shadows must remain below the character bodies.
   Watch grazing camera angles for beach flicker, floating blobs or z-fighting.
6. In the Remote scene tree confirm `Actor/ShadowAnchor/WorldBlobShadow`, no
   `ShadowSprite3D`, and no `<ActorName>BlobShadow` siblings under `World`.
   Tweak width/depth/opacity/ground_offset on one shadow and verify neighboring
   actors do not change.

Visual appearance, opacity preference and overlap aesthetics remain **pending**
these rendered checks; headless QA does not establish visual correctness.
