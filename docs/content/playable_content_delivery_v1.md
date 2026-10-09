# Playable Content Delivery v1

## Delivered encounters

Visuals are provisional catalogue assignments, not final lore identities. No opponent decks, card rules, progression data, technique prerequisites or teacher IDs changed.

| Opponent ID | Physical location / actor node | Catalogue visual | Normal duel gate | Root position (x,y,z) |
|---|---|---|---|---|
| `pier_apprentice` | Beach / `World/CardsPierApprentice/CardChallenge` | Rod Angler (`placeholder_14bf342a`) | Card case; rank 1; defeat beach_trader | (-2.75, 0, 0.55) |
| `gearwright` | Wyndia Ocean outpost / `World/CardsGearwright/CardChallenge` | Lanky Worker (`placeholder_68024840`) | Card case; rank 1; defeat pier_apprentice | (-2.75, 0, 0.6) |
| `dock_bruiser` | Wyndia Ocean outpost / `World/CardsDockBruiser/CardChallenge` | Blue Cap Stout Traveler (`placeholder_7f1b19bc`) | Card case; rank 2; defeat gearwright | (0.0, 0, 0.65) |
| `storm_captain` | Wyndia Ocean outpost / `World/CardsStormCaptain/CardChallenge` | Fishing Captain (`fisher_captain_01`) | Card case; rank 4 | (2.8, 0, 0.65) |
| `highland_keeper` | Lyp Lake outpost / `World/CardsHighlandKeeper/CardChallenge` | Violet Armored Traveler (`placeholder_7d53dc6e`) | Card case; rank 2 | (-2.75, 0, 0.6) |
| `tide_oracle` | Lyp Lake outpost / `World/CardsTideOracle/CardChallenge` | Pale Hood Traveler (`placeholder_f3876069`) | Card case; rank 3 | (0.0, 0, 0.65) |
| `marsh_keeper` | River outpost / `World/CardsMarshKeeper/CardChallenge` | Green Turban Traveler (`placeholder_ff1c0303`) | Card case; rank 2 | (-2.75, 0, 0.6) |
| `wandering_sage` | River outpost / `World/CardsWanderingSage/CardChallenge` | Green Bearded Traveler (`placeholder_e1466c4f`) | Card case; rank 4 | (0.0, 0, 0.65) |
| `lantern_gambler` | Chiqua Supply outpost / `World/CardsLanternGambler/CardChallenge` | Turban Trader (`placeholder_3cb9da3b`) | Card case; rank 3 | (-2.75, 0, 0.6) |
| `ash_champion` | Chiqua Supply outpost / `World/CardsAshChampion/CardChallenge` | Gold Armored Stout Traveler (`placeholder_c3997e38`) | Card case; rank 5; defeat storm_captain | (0.0, 0, 0.65) |

The existing `beach_trader` encounter remains unchanged. The complete 11-opponent registry now has exactly one physical world provider per opponent. Authored native/preferred/reward card IDs, archetypes, rule overrides, rematch evolution and deck budgets were inspected and remain in the existing registry resources. Coastal early opponents stay near Beach/Ocean; wardens and sages occupy Lake/River; the gambler/champion use Chiqua as provisional encounters within the currently available five-location slice.

## Delivered lessons

| Technique | Location / provider | Catalogue visual | Teacher / prerequisites |
|---|---|---|---|
| `structure_fighting` | Lyp Lake outpost / `World/LessonStructureFighting/MasterLesson` | Dark Hat Traveler (`placeholder_d1282736`), temporary Master stand-in | `master_structure_hunter`; Read Structure + Line Feel |
| `snag_escape` | River outpost / `World/LessonSnagEscape/MasterLesson` | Brown Hat Traveler (`placeholder_78f1768c`), temporary Master stand-in | `master_structure_hunter`; Read Structure |

These are instructional lessons through `FishingMasterLessonNPCBase`. K opens the existing Master dialogue and teaches the canonical authored technique through `FishingMasteryService.learn_technique`. Missing prerequisites produce explanatory dialogue without granting anything. Revisiting repeats the authored instruction. Developer Mode uses the existing mastery access policy to bypass prerequisites for testing; it does not introduce a new mechanic or progression store.

## Composition and placement

Each encounter inherits its existing catalogue actor scene. ActorRoot remains the physical CharacterBody3D, with the same GroundPresentation, directional SpriteFrames, shared shadow/collider family and stationary non-pushing policy. A zero-offset role child uses exported NodePaths to the actor-owned sprite and existing interaction Area. This keeps art separate from gameplay role. Default paths on existing providers retain all previous scene behavior.

The new encounter Areas retain the catalogue radius and position, with mask 3 to detect both supported player layers (the authored worlds override Ryu to layer 1; the standalone player uses layer 2). The existing router still owns C/K selection. Opponent access is evaluated by the existing game/registry; a locked Normal encounter cannot open dialogue or a match. Developer Mode can travel to and start every encounter using its existing temporary practice deck.

Rendered testing rejected an initial row outside the visible land mesh. Final placements are on the existing Beach mesh, with no visual-Y offsets or scene geometry changes. QA verifies the center and footprint perimeter against actual mesh triangles, distinct body footprints, player capsule approaches, shore/transit lanes and shop/travel approach axes. Interaction-range Areas, original actors, and destination metadata are unchanged.

`provider_bindings_v1.json` remains validation metadata rather than a gameplay registry: twelve scene bindings added, twelve deferred exceptions removed. All 64 active providers validate. The sole remaining encoded exception is the intentionally disabled River trader (no River trade authored); it is not a missing opponent or lesson.

## QA commands and results

Run from the project root with the installed Godot 4.7.2 executable (`$Godot` below). Every runtime fixture uses isolated userdata. No ordinary save was modified.

```powershell
$Godot = 'C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe'
& $Godot --headless --path . --script scripts/qa/playable_content_delivery_qa.gd
& $Godot --headless --path . --script scripts/qa/playable_content_delivery_qa.gd -- --mobile
& $Godot --path . --rendering-method gl_compatibility --script scripts/qa/playable_content_delivery_qa.gd -- --rendered
```

The focused fixture uses actual world travel, physics Area detection, facing selection, routed C/K, NPC dialogue completion and five-card match startup for each opponent in DEV and unlocked Normal. It also checks locked Normal card/rank/prerequisite gates, runtime-only practice cards, both lessons before/after prerequisites and via live DEV mastery, and cleanup with zero orphan nodes. Normal unlocked card tests seed authored acquisition/results only in their disposable save.

| Suite | Final result | Command suffix (after `$Godot --headless --path .`) |
|---|---|---|
| Content registration | 2227/2227; 64 active providers, zero invalid bindings | `--script scripts/qa/content_registration_qa.gd` |
| New native encounter/lesson delivery | 1453/1453 | `--script scripts/qa/playable_content_delivery_qa.gd` |
| New mobile harness delivery | 1453/1453 | `--script scripts/qa/playable_content_delivery_qa.gd -- --mobile` |
| New rendered Compatibility delivery | 1453/1453; all 12 encounter captures produced | See rendered command above (no `--headless`) |
| Triple Triad backend | 101/101 | `--script scripts/qa/session_contract_runner.gd` |
| Mastery / existing Structure Hunter / Line Fighter | 64/64; 25/25; 30/30; remaining existing Master suites also pass | Same explicit session runner |
| Campaign Loop / fresh save | 14/14; 55/55 | Same explicit session runner |
| Full fishing regression | 22950/22950; zero orphan nodes | Same explicit session runner |
| World locations | 598 checks, zero failures | `--script scripts/qa/world_location_access_qa.gd` |
| Interaction | 93/93 | `--script scripts/qa/world_interaction_qa.gd` |
| Hard body collision | 96/96; maximum passive player displacement 0 | `--script scripts/qa/world_actor_collision_qa.gd` |
| Collision policy v2 | 200/200 | `--script scripts/qa/world_actor_policy_v2_qa.gd` |
| Grounding | 1108/1108 | `--script scripts/qa/world_grounding_standard_qa.gd` |
| Catalogue | 2589/2589 | `--script scripts/qa/npc_catalog_qa.gd` |
| World population | 449/449 | `--script scripts/qa/npc_world_population_qa.gd` |
| Scene/resource serialization | 927/927; 78 actor scenes | `--script scripts/qa/scene_resource_integrity_qa.gd` |
| Developer Mode | 89/89 | `--script scripts/qa/developer_playtest_qa.gd` |
| Mobile harness | 182/182 | `--script scripts/qa/mobile_portrait_harness_qa.gd` |
| Whitespace | PASS | `git diff --check` |

The economy balance guardrails remain **22/24**, with the same two H12 alerts (20975 > 15500; 10537 > 8000). Structural campaign health passes; no balance values or classifications changed. The authored Ash Champion deck still emits its existing recovery-budget warning (36 -> 38); no deck budgets or rules were modified.

Failed intermediate runs were not accepted: initial scene-reference insertion order was corrected; fresh catalogue sensors were corrected for the authored player layer; fixture floating-point and dialogue-to-deck pause assumptions were corrected; the rendered off-land placement was replaced and actual-mesh coverage added; a fixture type-inference error was fixed; approach QA now proves an unobstructed side rather than demanding passage through the existing Beach merchant. Final results above are reruns of the final files, not inferred counts.

Rendered captures: `build/mobile-web/content-delivery-rendered/*.png` (ignored QA artifacts). Native rendered Compatibility execution is not physical Safari acceptance; refresh the rebuilt Web export and visit the new encounters on the phone. Existing GLES shader-cache write diagnostics may appear in this isolated rendered fixture; no project script failures are accepted.

## Files for this pass

Existing changes from the preceding scene-authoring stability pass were preserved and are not counted as this pass.

- `actors/FishingTestScene_V2.tscn`
- `actors/locations/WyndiaOceanOutpost.tscn`
- `actors/locations/LypLakeOutpost.tscn`
- `actors/locations/RiverFishingOutpost.tscn`
- `actors/locations/ChiquaSupplyOutpost.tscn`
- `actors/npc/encounters/ash_champion.tscn`
- `actors/npc/encounters/dock_bruiser.tscn`
- `actors/npc/encounters/gearwright.tscn`
- `actors/npc/encounters/highland_keeper.tscn`
- `actors/npc/encounters/lantern_gambler.tscn`
- `actors/npc/encounters/marsh_keeper.tscn`
- `actors/npc/encounters/pier_apprentice.tscn`
- `actors/npc/encounters/snag_escape.tscn`
- `actors/npc/encounters/storm_captain.tscn`
- `actors/npc/encounters/structure_fighting.tscn`
- `actors/npc/encounters/tide_oracle.tscn`
- `actors/npc/encounters/wandering_sage.tscn`
- `scripts/triple_triad/triple_triad_opponent_npc.gd`
- `scripts/mastery/fishing_master_lesson_npc_base.gd`
- `scripts/mastery/fishing_master_authored_lesson.gd` and `.uid`
- `data/world/provider_bindings_v1.json`
- `scripts/qa/playable_content_delivery_qa.gd` and `.uid`
- `docs/content/playable_content_delivery_v1.md`
- `export/index.html`, `export/index.pck` — regenerated Linux Web build

## Remaining content

No registered opponents or mastery techniques remain deferred for lack of a physical provider. Final visual/lore assignments remain provisional. This delivery does not invent a River trader, new locations or final character identities.

## Web rebuild

```powershell
& .\tools\mobile\build_mobile_playtest.ps1
```

The existing Linux/WSL builder validates the PCK project.binary ECFG entry before publishing. HTTPS is not restarted. Build completed successfully using Linux Godot 4.7.2. Published `export/index.pck` is **32,142,136 bytes**; `project.binary` is **9,944 bytes** with a valid **ECFG** header. The existing HTTPS server was neither started nor restarted. Safari is ready to refresh.
