# World Actor Collision Ownership v1

## Root cause and inspected actors

Ryu is a CharacterBody3D and runs move_and_slide even with world movement disabled. Previously his default moving-platform floor mask included world actors. Crabs were AnimatableBody3D roots; Card Maker was a Node3D with a moving AnimatableBody3D BodyCollider. Their locomotion wrote positions directly without checking collision. Those bodies moved into Ryu and supplied platform velocity to his slide solver.

A four-second reproduction using real player/actor scenes and production movement methods displaced Ryu by 0.4540219 world units for the crab (including vertical displacement) and 1.8489048 for Card Maker. Platform velocities were 0.22 and approximately 0.54 respectively, despite disabled player movement.

Merchant, Crafter, all 14 Fishing Master scenes, Triple Triad opponent, and reward/request NPC bases were inspected. Their blockers are stationary StaticBody3D nodes, normally layer/mask 1/1, with no autonomous root translation. Their interaction Areas retain layer 0/mask 3. They require no migration. Both beach crabs use the shared critter scene. Card Maker is the mobile humanoid affected here.

## Collision ownership

Both roaming actor classes now inherit AutonomousWorldActor, a CharacterBody3D policy using move_and_collide for collision-safe travel. Local patrol displacement is converted through the parent's world basis. Movement accepts only travel up to contact and never modifies another body's transform or velocity. Collision returns control to the existing idle/repath logic: crab waits then chooses another direction; Card Maker pauses then proceeds to the next patrol leg. Final waypoint movement is collision-tested too.

Card Maker now has one physical root and its existing capsule directly beneath that root. There is no separate BodyCollider or home-position blocker. The shape footprint, stance, sprite, ShadowAnchor, interaction Area and presentation footprint adjustments are preserved.

WorldActors uses physics layer 5 (bit 16); roaming actor mask is 19 (environment, either existing player layer, other roaming actors). Player mask is 17 (environment plus roaming actors). Keeping actor bodies outside player bits 1/2 prevents unchanged player-only interaction Areas from treating the newly converted CharacterBodies as players.

The player's floor/wall platform masks are zero and platform-on-leave is DO_NOTHING as secondary protection. No player position reset or fishing-anchor teleport was added. QA also restores the legacy player platform masks and still measures zero displacement, proving the actor movement change works independently.

## Files changed by this pass

- actors/BeachFishingCritter.tscn
- actors/ExplorationPlayer_V2.tscn
- actors/FishingCardMakerNPC.tscn
- project.godot
- scripts/world/beach_fishing_critter.gd
- scripts/economy/fishing_card_maker_npc.gd
- scripts/world/autonomous_world_actor.gd and .uid
- scripts/qa/beach_collision_qa.gd
- scripts/qa/world_actor_collision_qa.gd and .uid
- docs/world_actor_collision_ownership_v1.md

Other existing worktree modifications are not part of this pass. No camera, fishing mechanics, economy, telemetry, location, animation, interaction-range or shadow code was changed.

## Runtime verification

Godot 4.7.2 was used. Commands below use `godot` to denote the executable. Runs supplied artifact log paths; runtime suites use isolated userdata and do not use the normal save.

| Command | Actual result |
| --- | --- |
| godot --headless --max-fps 240 --path . --quit-after 40000 --script res://scripts/qa/world_actor_collision_qa.gd | 158/158; max passive player displacement 0.0, epsilon 0.00001 |
| godot --headless --path . --quit-after 1800 --script res://scripts/qa/beach_collision_qa.gd | 65 checks, 0 failures |
| godot --headless --path . --quit-after 1800 --script res://scripts/qa/world_interaction_qa.gd | 93/93 |
| godot --headless --path . --quit-after 1800 --script res://scripts/qa/world_character_shadow_qa.gd | 898 checks, 0 failures |
| godot --headless --path . --quit-after 12000 --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions | Camera 120/120; full fishing 22950/22950; Fight 24/24; Presentation 10/10; Stability 27/27 |
| godot --path . --max-fps 60 --fixed-fps 60 --quit-after 1800 --write-movie actor-contact.avi --script res://scripts/qa/world_actor_collision_qa.gd -- --rendered --capture-dir=ARTIFACT_DIRECTORY | 4/4; both native actor callbacks contact Ryu; max displacement 0.0 |
| git diff --check | Passed |

The new physics QA exercises multi-second contact, original player platform settings, reciprocal player walking, native patrol/roaming callbacks and interaction-layer exclusion. It also loads the current FishingTestScene_V2 with real game-mode movement lock, IN_WATER/FIGHT/LANDING/WAIT_RESULT phases, real catch presentation, real merchant dialogue and paused trade UI. Both actor types remain physical obstacles throughout these cases. Existing beach QA verifies the current-position Card Maker collider, absence of the old blocker, gathering non-blocking behavior and unchanged interaction footprint.

Rendered QA uses real actor/player scenes and native physics callbacks in a controlled lit-independent fixture. Both contact captures were inspected; an approximately eight-second recording captures approach, stop and subsequent idle/repath. This is rendered physics evidence, not manual approval of every interaction in the normal beach scene. Capture output defaults to the temporary directory and can be overridden with --capture-dir; no production diagnostics were added.

Known unrelated warnings remain visible: the two provisional H12 economy balance alerts (22/24 guardrails) and the expected Triple Triad backend-not-ready QA guard. They were not suppressed or changed.

## Normal-play visual follow-up

In FishingTestScene_V2, let each crab and Card Maker contact idle Ryu and fishing Ryu; check that stops/turns feel natural and do not jitter. Repeat through a bite, landing, catch screen, dialogue and trade menu. Walk Ryu into a stationary actor; confirm he stops/slides without shoving it. Watch Card Maker move away from home; confirm its body and shadow follow the root and no home blocker remains. The physics invariants are verified, but normal-beach visual pacing remains a manual check.
