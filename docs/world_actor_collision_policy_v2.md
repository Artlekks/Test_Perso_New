# World Actor Collision Policy v2

## Categories and physics layers

| Category | Body / collision policy |
| --- | --- |
| Static environment | Existing StaticBody3D/environment layer 1; hard collision |
| Important stationary humanoid | Existing StaticBody3D, layer/mask 1/1; no locomotion or pushing |
| Moving humanoid | CharacterBody3D physical root, layer 16/mask 19; collision-tested movement plus separate player avoidance Area |
| Small ambient crab | Node3D visual/roaming root; no PhysicsBody3D; proximity Area layer 0/mask 3 |
| Interaction Area | Detection only; existing layer 0/mask 3 and range preserved |

Ryu retains layer 2 in the prefab (layer 1 in Beach), mask 17, platform_floor_layers=0, platform_wall_layers=0, platform_on_leave=DO_NOTHING. No v2 player/camera code or scene settings changed. Previously the original Animatable crabs could carry Ryu; v1 removed carry but retained hard crab geometry that could be classified as floor. V2 removes that geometry entirely. Hard humanoids still collide, while proximity and interaction sensors have no collision surfaces.

The player code was inspected: horizontal move_and_slide, no gravity, step-up logic or custom floor locomotion. This pass adds no grounding system or camera compensation. Runtime tests use authored player/NPC heights and show that normal ground-level NPC contact does not create a floor/platform or change Ryu's Y. Crab overlap creates no floor under any placement because there is no physics body.

## Humanoid movement

AutonomousWorldActor now supplies a player-only avoidance sensor independently of interaction range. Exported defaults: sensor radius 0.85, protected clearance radius 0.48, decision cooldown 0.8 seconds. It filters the existing fishing_player group, predicts intersection with the intended horizontal route and checks candidate passing motions against physical obstacles. It commits to one passing side until clearance/cooldown, checking 60/90/120-degree alternatives instead of alternating sides each frame. This is local steering for existing patrols, not a new navigation/path system.

Card Maker applies that steering to the existing waypoint leg and animates the actual chosen movement direction. If no safe passing motion exists or move_and_collide reports contact, he stops, clears velocity, sets locomotion_blocked, plays idle and waits for his existing 1.75–4.25-second pause before choosing the next authored patrol leg. Final waypoint travel is also collision-tested. Successful next-leg startup clears blocked state. Normal patrol resumes when space clears. His physical root/capsule and ghost-collider fix remain intact. Dialogue/workshop, interaction range, sprite assets, smoke disabled state and shadows are unchanged.

## Ambient crabs

Both beach crabs use the same scene. Their former CharacterBody3D roots and hard sphere are replaced with Node3D roots and a detection-only ProximityArea sphere of radius 0.4. The root world positions, sprite offsets, shadows, roaming rectangles and authored speed remain unchanged.

Every 0.6 seconds at most, a nearby player can cause the crab to select an available authored diagonal away from him. Candidate probes must remain inside the original roaming rectangle. Translation remains bounded to that rectangle and its original Y. Ryu can walk through the footprint; neither actor receives physics displacement from the other. Constrained space may permit visual overlap, deliberately without adding a hard blocker.

## Files changed in v2

- actors/BeachFishingCritter.tscn
- scripts/world/autonomous_world_actor.gd
- scripts/world/beach_fishing_critter.gd
- scripts/economy/fishing_card_maker_npc.gd
- scripts/qa/beach_collision_qa.gd
- scripts/qa/world_actor_collision_qa.gd
- scripts/qa/world_actor_policy_v2_qa.gd and .uid
- docs/world_actor_collision_policy_v2.md

The existing dirty worktree and v1 changes remain. No v2 changes to camera logic, fishing mechanics, economy, telemetry, progression, interaction ranges or shadow code.

## Verification

Godot 4.7.2 executable: `C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe`. Commands use `godot` below as shorthand and supplied external log-file paths. Full-scene suites use isolated userdata rather than the normal save.

| Command | Result |
| --- | --- |
| godot --headless --path . --max-fps 240 --quit-after 12000 --script res://scripts/qa/world_actor_policy_v2_qa.gd | 200/200 |
| godot --headless --path . --max-fps 240 --quit-after 40000 --script res://scripts/qa/world_actor_collision_qa.gd | 96/96, max passive Ryu displacement 0.0, epsilon 0.00001 |
| godot --headless --path . --quit-after 40000 --script res://scripts/qa/beach_collision_qa.gd | 65 checks, zero failures |
| godot --headless --path . --quit-after 40000 --script res://scripts/qa/world_interaction_qa.gd | 93/93 |
| godot --headless --path . --quit-after 40000 --script res://scripts/qa/world_character_shadow_qa.gd | 898 checks, zero failures |
| godot --headless --path . --quit-after 40000 --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions | Full fishing 22950/22950; camera 120/120; Fight 24/24; Presentation 10/10; Stability 27/27; Card Maker 10/10 |
| godot --path . --max-fps 60 --fixed-fps 60 --quit-after 4000 --write-movie ARTIFACT.avi --script res://scripts/qa/world_actor_policy_v2_qa.gd -- --rendered --capture-dir=ARTIFACT_DIRECTORY | Rendered actual beach: 200/200 |
| git diff --check | Passed |

Actual beach avoidance measured max Ryu displacement 0.0, lateral detour 0.59709 and forward progress 1.59288 world units on the deliberately obstructed QA route. There was at most one stationary walk tick while state changed, with no sustained walk-in-place. Unavoidable hard contact explicitly idled, and reciprocal player walking remained blocked without either actor displacement or vertical change.

The v2 suite walks Ryu through an actual crab footprint, checks proximity response, absence of physics bodies on both beach crabs, settled camera height and unchanged floor state. The safety suite deliberately disables proactive sensing to test the remaining hard-body fallback through real IN_WATER, FIGHT, LANDING, catch-result, merchant dialogue and trade UI. It separately overlaps a live ambient crab with Ryu in each fishing phase and verifies fixed anchor and ongoing roaming.

Rendered tests ran the current FishingTestScene_V2 with the real Card Maker, crab, camera and session bootstrap. Controlled player/route placements are QA-only; authored scene transforms were not edited. Approach/detour and crab-proximity frames were inspected. This is automated rendered runtime verification, not a claim that a human has approved every normal-play layout. Check prolonged obstruction and narrow passages manually for preferred patrol pacing.

Initial camera-height QA failed because it sampled immediately after relocating Ryu; the test now waits for existing camera smoothing to settle before measuring. A rendered run also logged a Godot shader-cache write error at `_save_to_cache`; the physics suite completed 200/200 and images rendered. No gameplay errors were suppressed. The pre-existing two H12 balance warnings and expected Triple Triad backend guard remain visible.
