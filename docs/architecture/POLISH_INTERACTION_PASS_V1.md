# Polish & Interaction Pass v1

## Input contract

`Exploration` constructs one scene-local `WorldInteractionRouter` with the
existing player and GameMode. Registered 3D world actors expose
`is_world_interaction_available(event)` and `interact_from_world(event)`;
their existing dialogue, service, reward and gathering behavior stays local.
The base lesson/reward classes register their derived NPCs as well.

The router accepts only fresh key presses while the tree is unpaused and
GameMode is EXPLORATION. It never consumes fishing-mode K, including during
entry, casting, water, fights and presentation. It observes key releases even
while paused so a world press cannot repeat into another target or modal.
If no target qualifies, exploration receives the event normally.

Both player world-facing and target bearing are quantized to eight sectors.
The facing sector and its two immediate neighbors qualify: NW accepts W/NW/N.
Selection is nearest horizontal distance, then strongest facing alignment,
then lexical scene path. Selection runs only on an interaction press, not per
frame. K/Enter talk/gather and the dedicated C card action retain their current
actor-specific predicates. The unused Area2D reward template is unchanged;
the router is the interaction owner for the current 3D world.

New world actors should join `world_interaction_targets`, implement those two
methods, and avoid `_input`/`_unhandled_input` interaction callbacks.

## Ground presentation

The shared gathering Sprite3D uses alpha blending and priority -110, below
the existing character range -90..90. Alpha scissor previously put the ground
object into the opaque/depth-writing path. World position, orientation,
pixel size, collision/range, depletion and grants are unchanged. Sea Glass
inherits this rule. The global character/shadow system is unchanged.

## Card Maker

All four walk cycles contain six equal-duration frames at 8 FPS (0.75 s/cycle).
Sprite pixel size is the default 0.01 world units/pixel. Inspection of the
lowest nine occupied pixel rows gives these horizontal foot spans, in pixels:

- NE: [12,35), [9,38), [12,35), [18,33), [20,30), [18,33).
- SE: [16,33), [17,27), [16,33), [12,36), [10,38), [12,36).

Those are substantial step changes rather than a tiny shuffle. Translation
increases from 0.18 to 0.54 units/s: 2.25 to 6.75 pixels/frame, or 13.5 to
40.5 pixels/cycle. FPS, patrol waypoints and pauses remain unchanged. Godot
visual inspection is still needed to judge the final perceived stride.
Entering/exiting the radius changes range tracking only. Patrol stops when
dialogue or the workshop actually opens, rather than on a failed attempt.

## Smoke source diagnosis and art correction

`AnimatedSprite3D.offset` is constant (0,-2), and the patrol process exits
while `_special_playing` is true. No smoke code moves the NPC transform.
The atlas itself is 1632x897. Smoke uses 34 cells at (48*i,828), each 48x66;
idle/walk use 48x69 canvases. No AtlasTexture margins compensate for that.

Indices below are zero-based. Smoke's last occupied foot row is y=64 in every
frame; idle SE's is y=63. With centered canvases, that is a 2.5-pixel vertical
anchor difference. Re-export every smoke frame on a 69-pixel-high canvas and
translate its character content up exactly 1 pixel to share the idle foot
baseline. There is no measured common horizontal body offset to correct.

The plume reaches the right cell boundary in frames 19..24. Neighboring plume
fragments appear on the left of frames 21..26. Measured fragment bounds:

| Smoke frame | Left fragment local position |
|---|---|
| 21 | x=0, first occupied plume row y=7 |
| 22 | x=0, first occupied plume row y=5 |
| 23 | x=0, first occupied plume row y=3 |
| 24 | x=0, first occupied plume row y=2 |
| 25 | x=0, first occupied plume row y=7 |
| 26 | x=2, first occupied plume row y=10 |

Repack the plume on wider independent cells, removing neighboring-frame
fragments and retaining each frame's complete plume. For a 96x69 canvas,
translate the original character content by (+24,-1) pixels in every frame
to preserve the shared centered anchor. Merely changing the current atlas
crop width would include the next character, so it is not a safe code fix.
Smoke is temporarily disabled with `smoke_enabled=false`. No NPC/collider or
shadow compensation was introduced. Original art/resources remain intact.

## QA

New save-free executable suite:

```text
godot --headless --path . --script res://scripts/qa/world_interaction_qa.gd
```

It tests the real router with isolated targets: all 64 facing combinations,
deterministic ties, range/availability exclusion, nearest target, repeated
held presses, echoes, rapid released taps, modal pause, fishing mode, absent
player/mode, removed targets, ground render settings and Card Maker defaults.
The fishing check tests the mode boundary, not individual fishing mechanics.
It does not open or mutate player saves. Existing suites were not changed.

Changed files:

- `scripts/world_interaction_router.gd` (new)
- `scripts/qa/world_interaction_qa.gd` (new)
- `scripts/exploration.gd`
- `scripts/beach_gathering_node_3d.gd`
- `actors/BeachGatheringNode3D.tscn`
- `scripts/beach_crafter_npc.gd`
- `scripts/beach_merchant_npc.gd`
- `scripts/economy/fishing_card_maker_npc.gd`
- `scripts/mastery/fishing_master_lesson_npc_base.gd`
- `scripts/mastery/fishing_master_still_water_npc.gd`
- `scripts/progression/fishing_reward_claim_npc_base.gd`
- `scripts/triple_triad/triple_triad_competition_interaction_3d.gd`
- `scripts/triple_triad/triple_triad_harbor_request_board.gd`
- `scripts/triple_triad/triple_triad_opponent_npc.gd`
- `scripts/triple_triad/triple_triad_world_reward_trigger_3d.gd`
- This pass note (new)

Godot was not located in the execution environment, so this suite and existing
Godot suites have not been executed. Static reference/declaration checks and
diff validation do not establish parser or runtime correctness.

Visual acceptance in Godot: rotate the camera through four angles; test NW
targeting and overlapping NPC ranges; cast/hook/reel beside NPCs/pickups;
overlap Ryu/NPCs with each ground sprite and Sea Glass; walk into/out of Card
Maker range; interact/cancel/resume patrol; confirm smoke stays disabled and
the existing shadow system behaves identically.
