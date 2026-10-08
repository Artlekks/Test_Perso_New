# NPC Asset Catalogue v1 + Developer Playtest Mode v1

Implemented against the current project on 2026-10-08. Existing source PNGs,
production character scenes, camera values, dialogue style, prices and save
schema were preserved. The independent preview is development content.

## Inventory and catalogue

`asset_inventory.json` is the complete machine-readable inventory: **33 character
sheets: 7 NPC sheets and 26 player sheets**. It records dimensions, every authored
AtlasTexture region, animation/frame order/FPS, existing SpriteFrames and direct
scene references. There are no magenta pixels in the seven existing NPC sheets.
Six existing NPC SpriteFrames resources are reused; no converted art is duplicated.
Player art remains in its existing player resource and animation system.

| Source under assets/sprites/npcs | Size | Existing slicing |
|---|---:|---|
| beach_merchant/Line_03.png | 840x44 | 21 40x44 Bag_Search frames |
| beach_merchant/Line_09_B.png | 160x56 | 4 40x56 Stand_Interest frames |
| fishing_master/beach_Crafter.png | 1240x40 | 31 40x40 Idle frames |
| fishing_master/smoking_dog.png | 1144x54 | 26 44x54 Idle frames |
| fishing_card_maker/fishing_captain_atlas.png | 1632x897 | 48x69 idle/walk cells; existing smoke slices retained but unused |
| beach_critters/crab_directional_atlas.png | 256x48 | 32x24 cells, eight idle views/two walk strips |
| beach_critters/fishing_critters_atlas.png | 320x48 | 32x24 cells, green/red, five views each |

**Seven visual profiles, seven ready-to-drag scenes, seven catalogue entries**:

| ID / development name | Tags | Authored coverage and animations | Collider | Shadow |
|---|---|---|---|---|
| merchant_heavy_01 / Heavy Merchant | merchant, special_vendor | ONE_VIEW; Bag_Search, Stand_Interest, 5 FPS | humanoid_heavy | humanoid .22x.22, .65 |
| seated_crafter_01 / Seated Crafter | harbor_worker, quest_placeholder | ONE_VIEW; Idle, 5 FPS | seated_npc | humanoid .22x.22, .65 |
| smoking_traveler_01 / Smoking Traveler | traveler, quest_placeholder | ONE_VIEW; Idle, 5 FPS | seated_npc | humanoid .22x.22, .65 |
| fisher_captain_01 / Fishing Captain | fisher, card_opponent | SPECIAL; idle_ne/nw/se/sw at 6 FPS, walk_ne/nw/se/sw at 8 FPS | humanoid_standard | humanoid .22x.22, .65 |
| crab_small_01 / Small Crab | ambient_creature | EIGHT_DIR idle; walk_nw/sw at 8 FPS, explicit NE/SE mirrors | ambient_creature | small_creature .10x.10, .60 |
| creature_green_01 / Green Small Creature | ambient_creature | SPECIAL; green_s/se/e/ne/n, two frames at 10 FPS | ambient_creature | small_creature .10x.10, .60 |
| creature_red_01 / Red Small Creature | ambient_creature | SPECIAL; red_s/se/e/ne/n, two frames at 10 FPS | ambient_creature | small_creature .10x.10, .60 |

Merchant's two strips form one visual identity. Green/red share the existing
SpriteFrames without copying their frames. Captain smoke is never selected by
the catalogue actor or preview; the production Card Maker stays smoke-disabled.

The four external reference assignments (`teleporter_guardian_01`,
`master_bird_01`, `master_hat_01`, `master_hat_02`) remain **UNCONFIRMED**. The user
has not mapped these images to files; no role-specific scenes or art were invented.

Art gaps: one-view humanoids need additional facing and locomotion drawings;
Captain needs cardinal drawings for true eight-view coverage; crab walk needs
additional authored views; green/red creatures need western views and identified
locomotion groups. Nearest-view fallback never claims those missing views exist.

## Architecture and use

`CatalogueNPCActor` extends the production `AutonomousWorldActor`:

```
CharacterBody3D root (feet, Y=0)
  CollisionShape3D (profile family)
  GroundPresentation (existing shared scene/code)
    VisualAnchor / AnimatedSprite3D
    ShadowAnchor / WorldBlobShadow
  InteractionArea (no gameplay role handler yet)
  PlayerAvoidanceSensor (existing movement policy)
```

`NPCVisualProfile` extends `WorldActorPresentationProfile`; it inherits the one
grounding/shadow/directional source of truth. Added data covers identity, frames,
directional mode/coverage, default animation, animation speed multiplier, collider,
shadow family, movement capability and role tags. All six requested directional
modes are declared; explicit prefixes/aliases use the existing camera-relative
resolver. Existing animation timings are preserved; future untimed animation
manifests use one central 8 FPS default. `animation_speed` in the inspector scales
the authored cadence, rather than rewriting shared SpriteFrames.

Collider family defaults (radius/height): humanoid_standard .18/.52;
humanoid_heavy .24/.56; humanoid_small .14/.42; seated_npc .22/.44;
ambient_creature .08/.16 and ground_prop_small .12/.24 have hard collision disabled.
Hard actors use layer 16/mask 19, zero platform layers, collision-safe autonomous
motion. Presentation fallback respects the shared `profile_owned_collision`
marker. It cannot enlarge these profiles or create an ambient floor body.

Drag `actors/npc/catalog/NPC_<id>.tscn` into a world, set X/Z and leave Y=0.
No scene sprite/shadow compensation is required. Assign role/dialogue components
later. Captain optionally supports `patrol_enabled` through the existing avoidance
policy; it defaults OFF. Interaction Areas do not provide a fake gameplay action.

Open `actors/npc/NPC_Catalogue_Preview.tscn`, press F6. Q/E orbit, +/- zoom,
Space selects authored walk poses, I selects idle. Every entry is labelled and
instanced; missing walk groups retain their descriptive default pose. No preview
scene is mounted during normal play.

## Future ingestion

Place original PNGs under `assets/sprites/npc/source/` and provide a reviewed
`<name>.npc.json` with exact frame boundaries/semantic directions. For example:

```json
{
  "id": "robed_traveler_02",
  "name": "Robed Traveler",
  "source": "assets/sprites/npc/source/robed_traveler.png",
  "animations": [{"name": "idle_s", "rects": [[0, 0, 40, 56]]}],
  "default_animation": "idle_s",
  "mode": 0,
  "directions": ["S"],
  "collider": "humanoid_standard",
  "tags": ["traveler"],
  "note": "Placeholder; other views unconfirmed",
  "profile_overrides": {
    "feet_from_bottom_px": "4.0",
    "directional_animation_prefixes": "{\"idle\": \"idle_\"}",
    "default_directional_pose": "\"idle\""
  }
}
```

`profile_overrides` values are Godot resource literals; inherited grounding values
remain centralized in the profile. `fps` is optional in each animation (default
8); `movement`, `shadow`, and an existing `grounding_template` are optional.
For guide rectangles, set `magenta_border: true` and specify rectangles including
their border. Ingestion verifies all border pixels, trims only the one-pixel
border, validates bounds and rejects guide pixels in extracted frames. It uses
AtlasTexture references and never edits/resamples PNGs. Plain PNGs without reviewed
manifests are reported UNCONFIRMED, not guessed or discarded.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\npc\build_npc_catalog.ps1
```

This produces SpriteFrames (only for new sheets), visual profile, normalized scene,
catalogue entry and refreshed inventory. Re-running reuses existing resources;
IDs must be unique. The helper uses installed Python/Pillow; `-PythonPath` permits
another installation. Import in Godot and run `npc_catalog_qa.gd` after ingestion.

## Developer Playtest Mode

One transient, debug-build-only `DeveloperPlaytestService` is a child of persistent
`FishingSessionServices`. No new autoload or save field. `mode_changed` refreshes
runtime access/presentation. Desktop F5 defaults OFF. Dedicated mobile harness
defaults ON **after** normal session initialization and QA; scene handoffs retain
the current mode. Mobile indicator is at the gameplay/control boundary, desktop
indicator at the corner. Existing HUD/camera/layout stays intact.

Integrated seams:

* WorldLocations runtime snapshots, reachable destinations and validated travel.
  Explicit inventory/progression snapshots never receive overrides, including
  `_refresh_unlocks`; toggling cannot latch a travel flag.
* TripleTriadWorldGateway card access and opponent registry progression checks
  (case, rank, wins, prerequisites). Unknown/disabled opponents and encounter
  region/tag checks still fail. Authored acquisition snapshots stay real.
* Campaign presentation controller enables the existing card NPC, Card Maker,
  request/reward/championship interaction areas without granting rewards.
* Economy UI facade overrides authored purchase availability tags only inside a
  valid active provider context. Shop/recipe scope, provider metadata, prices,
  ownership and transaction costs remain authoritative. Manillo providers become
  reachable through authored travel; none currently has an additional independent
  progression gate. Crafter entry currently has no separate progression gate.
* Live-session FishingMasteryService allows prerequisite-gated lesson access in
  DEV; standalone mastery QA instances receive no override. Unknown techniques,
  wrong teachers and already-known checks still apply. Actual lesson success
  conditions remain unchanged; the toggle itself grants no technique or capability.

Toggle OFF immediately releases overrides and refreshes interaction policy.
Fresh Save Rehearsal and all four Campaign QA entry points explicitly force OFF.
Mobile normal-mode regression fixtures opt out of the mobile default. Balance
alerts remain visible and are never converted to passes by developer access.

### F10 and save safety

F10 opens the same FishingDebugMenu. Mobile SELECT sends canonical F10.
START/Space (or page button) switches PLAYTEST/FISHING QA. Up/down or stick selects;
left/right toggles mode/selects destination; A/K activates; B/I closes.
Exploration F10 is a paused modal with sole input ownership; the existing fishing
AIM debug path is retained. Quick travel closes the exploration modal before
requesting normal WorldLocations scene replacement. Fishing-owned/modal/busy,
unknown or missing scenes remain rejected.

PLAYTEST offers mode ON/OFF, access ALL, authoritative five-location selector,
Fishing Loadout, Card Loadout and Economy Wallet. The list is read from
WorldLocations, not a second hardcoded route table. Clear Test Loadout was omitted:
blind rollback could delete genuine items earned during the test session.

Mode toggle and travel-access queries are runtime-only. Loadouts are explicit
**persistent test-save mutations**: two of every authored lure, one of every rod;
five valid source cards (no starter-case claim); wallet set to 10,000 zenny.
Cards go through a guarded game facade and invalidate normal collection caches.
The fishing loadout supplies authored tackle, not fabricated fish/recipe costs.
Actual play can persist normal catches/trades/lesson rewards within the current
save; DEV is not a virtual transaction simulator.

Loadouts require DEV, harness authorization, custom userdata and an allowlisted
isolated namespace: `FishingGame-MobilePortraitPlaytest` or the unique
`CodexDeveloperPlaytestQA-*` fixture. Native paths must match the configured name;
Web uses its isolated browser origin/userfs plus harness authorization. Normal
desktop saves and arbitrary custom directories are blocked. Merely enabling DEV
never authorizes a normal save or grants inventory.

## Verification

Windows Godot 4.7.2 used for native QA. Standard invocation:

```powershell
& 'C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe' --headless --path . --script res://scripts/qa/<suite>.gd --log-file <log>
```

| Suite actually run | Result |
|---|---|
| npc_catalog_qa | 715/715 rendered Compatibility; frame validity/guide exclusion, profiles, preview, family ownership, actual actor/player physics |
| developer_playtest_qa | 73/73 final headless; earlier 69/69 rendered; same-state card/travel/shop/mastery gates, toggle restoration, all-file save-byte comparison, unlock refresh purity, actual C/A/SELECT/START, five actual scene transitions, aim preservation and explicit loadouts |
| mobile_portrait_harness_qa | 163/163 |
| mobile_web_parity_qa (Linux Web, actual DOM touch events) | 27/27; C/A, SELECT/F10, DEV and OFF, authored travel |
| world_interaction_qa | 93/93 |
| beach_collision_qa | 65 checks, zero failures |
| world_actor_collision_qa | 96/96; max passive displacement 0, epsilon .00001 |
| world_location_access_qa | 573 checks, zero failures |
| early_tackle_acquisition_qa | 61 checks, zero failures |
| world_economy_access_qa -- --structural-only | 81 checks, zero failures; foundation 13/13, economy/trade groups 208/208 |
| world_economy_access_qa (direct balance gate) | 80/81; intentionally exposes existing 22/24 balance target result |
| economy_health_classification_qa | 30/30; guardrails remain 22/24 |
| runtime_economy_reconciliation_qa | 1002/1002 (current committed suite count, not renamed to 1029) |
| world_presentation_tuning_qa | 265/265 |
| world_grounding_standard_qa | 1013/1025; same 12 failures reproduced on untouched committed HEAD |
| fishing_fight_camera_tracking_qa -- --regressions | 120/120 camera, 22,950/22,950 full fishing |
| startup QA within the isolated full fishing run | Triple Triad 101/101; dialogue 175/175; Campaign Loop/Director/Guide/Presentation 14/14,14/14,8/8,9/9; Fresh Save 55/55; Fight 24/24; Presentation 10/10; Stability 27/27 |
| git diff --check | PASS |

Rendered catalogue captures cover four camera directions and idle/walk. Native
portrait capture shows the PLAYTEST menu and DEV indicator. The isolated rendered
mobile fixture emitted shader-cache file-write errors (both native renderers);
headless QA and the browser fixture did not show those errors. They are reported,
not suppressed. Physical iPhone acceptance remains a user visual/input check.

Existing baseline discrepancy: all 12 beach gathering InteractionArea shape world
positions differ from `qa_physics_baseline.json`. An untouched `git archive HEAD`
copy produced exactly the same 1013/1025 result. No gathering position or stored
baseline was changed. The known shutdown-resource warning was not investigated.

Balance truth: sell-heavy H12 wallet 20,975 exceeds 15,500; balanced H12 wallet
10,537 exceeds 8,000. Neither prices nor ceilings were changed.

Production Web rebuilt with the existing default Linux/WSL command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1
```

Build complete; final PCK **31,342,384 bytes**, `project.binary` **9,944 bytes**,
valid **ECFG**. Basename remains index for HTML/JS/WASM/PCK. HTTPS stayed on
0.0.0.0:8060 with existing PID 2964. Refresh Safari; no server restart is needed.

Complete modified/created source files are listed in `files_changed.txt`.
