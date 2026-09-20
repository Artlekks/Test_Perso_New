# FishingGame Cleanup / Refactor Audit

## Result

This is the first structural stabilization pass after the core fishing loop became functional.
The candidate intentionally preserves the current scene/layout and gameplay architecture while removing proven prototype debris and fixing correctness issues found during the audit.

- Original archive files (including `.git` / `.godot`): **1434**
- Clean candidate files: **359**
- Original size: **179.6 MiB**
- Clean candidate size: **3.3 MiB**
- Removed project files: **379**
- Modified/rewritten files: **27**

## Correctness fixes applied

1. **Cast preview trajectory** — `caster.gd` had only half of a local-variable rename completed; the preview loop was still reading the `Node3D.position` property instead of its predicted position. All trajectory integration now uses `predicted_position`.
2. **Fish endurance database actually works** — `FishInstance.setup()` now copies `resistance_rounds`, `recovery_time_min`, and `recovery_time_max` from `FishData`. Species such as Whale/Spearfish can now use their authored endurance instead of silently falling back to one round.
3. **Fight input has one owner** — removed the stray global `_unhandled_input()` FIGHT controls. FIGHT S/K/A/D state now comes from the existing phase-gated `_process()` path.
4. **Duplicate release reaction removed** — releasing K previously triggered two fish movement reactions back-to-back (`react_to_release` + legacy `react_to_slack`). There is now one reaction.
5. **Duplicate tension simulation removed** — tension was advanced twice per frame. It is now one update; response constants were adjusted to preserve the established feel (`0.36` reeling, `0.30` release) and W/S resting bias is compensated.
6. **Conflicting fight-distance clamps removed** — `bait_V2.gd` kept the newer `fight_max_distance` system and removed an older clamp based on a `fight_start_distance` value that was never initialized.
7. **Fishing animation dead branch removed** — duplicate `Phase.IN_WATER` animation branch removed.
8. **Power-meter color system simplified** — old blue/red texture-switching code and resources removed; the active one-texture hue shader remains.
9. **Fishing spot population is now single-source** — removed the temporary manual `FishZone_V2.fish_population` fallback and duplicate `fish_ids` runtime metadata. `FishingSpotData.fish_population` is the authoritative runtime population.
10. **Development console spam removed** from Encounter/FishBehavior.

## Removed architecture / prototype debris

- PhantomCamera addon/autoload/plugin: active V2 scene no longer references it.
- AS2P addon: not enabled/referenced.
- Old V1 FishingTestScene, HUD, player, fish-zone, depth-zone, bait and power-meter scenes.
- Superseded prototype state-machine/controller scripts.
- Tracked `.tmp` scene saves.
- Blender `.blend1` backups.
- Old test FishData / test behavior profiles.
- Obsolete BOF4 bait test folder (`data/bof4/baits`); current default bait remains at `data/baits/default_bait.tres`, real lure DB remains at `data/bof4/lures`.
- Proven duplicate Marsh/river textures.
- Old red/blue tension textures.
- Old depth/running/test art that had no live V2 reference.

## Deliberately kept

- All 30 real FishData resources and behavior profiles.
- All 19 lure resources, 6 rod resources, spot resources, and trade resources — even where runtime UI for them is not built yet.
- Active editable art sources (`.ase`/`.aseprite`) corresponding to live UI/animation assets.
- The current embedded Fishing HUD and Fishing controller structure. They are large, but splitting them now would be a higher-risk architectural refactor rather than cleanup.

## Recommended next refactor (after this candidate passes playtest)

Do **not** immediately rewrite the whole working controller. First test this clean candidate. Then use the short Cursor session as an independent read-only architecture audit. After comparing findings, the next safe structural split would be:

- extract a reusable `FishingSystem.tscn` (Aim/Power/Caster/Encounter/etc.);
- extract the currently embedded Fishing HUD into one canonical `FishingHUD.tscn`;
- later split `fishing.gd` presentation/animation decisions from phase/input orchestration.

The old generic fishing state-machine scripts were removed and should not be revived just for abstraction.

## Validation performed here

- Explicit `res://` path scan after cleanup.
- Removed-file reference scan.
- Duplicate `class_name` scan.

A Godot executable is not available in this environment, so the final engine parse/runtime validation must be done by opening this candidate in Godot and pressing F5.
