# FishingGame Architecture — Pass 5: Safe Performance Polish

**Date:** 2026-09-27  
**Baseline:** Pass 4 system-ownership candidate

## Goal

Remove known unnecessary per-frame work without changing gameplay feel or
touching the camera while a framing regression is still queued for later.

## Ambient shadow bait lookup

Before Pass 5 every live FishShadowActor ran:

`get_tree().get_first_node_in_group("bait")`

every frame.

With normal populations this was tolerable, but the QA shadow count can rise
much higher and the cost scaled as:

`shadow count x SceneTree lookup x frame rate`

Now FishShadowPresence owns one cached bait reference.

Behavior:

- while a bait exists, the reference is reused with no SceneTree search;
- when no bait exists, Presence performs at most one lookup every 0.10 seconds;
- when the bait changes, Presence broadcasts it to all ambient shadows;
- a hooked shadow continues using its explicit hooked bait path.

FishShadowActor no longer performs a SceneTree bait lookup.

## Hidden menu updates

The closed FishingMenu still accumulates session time exactly as before, but it
no longer rewrites the invisible Time label every frame.

The formatted value is refreshed when the menu/main page refreshes.

## Deliberately deferred

### Camera projection optimization

The architecture audit noted that screen-boundary correction can perform
multiple `unproject_position()` probes.

That optimization is intentionally deferred because the user has also logged a
possible post-follow fisherman-framing regression. Camera behavior and camera
performance should be addressed together after architecture cleanup, not mixed
into this pass.

### Encounter group lookups

Encounter still queries the active bait/presence group at bite-decision events.
Those calls are not the per-shadow-per-frame hotspot removed here and are left
alone until profiling shows a need.

## Frozen behavior

Pass 5 does not modify:

- camera_rig.gd;
- bait_V2.gd;
- bait_visual_controller.gd;
- fishing.gd;
- FishingTestScene_V2.tscn;
- FishingMenu.tscn.

## Static validation

- per-shadow bait SceneTree lookups remaining: **0**
- centralized Presence bait lookup sites: **1**
- missing quoted res:// references: **0**
- duplicate GDScript function declarations: **0**
