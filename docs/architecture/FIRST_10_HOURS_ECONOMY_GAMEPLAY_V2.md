# First-10-Hours Economy Gameplay v2 — 4–10h acquisition spine

Implemented in the current project on 2026-10-07. Godot verification used 4.7.2.stable.official.ed1daf0bf, headlessly. No elapsed-time runtime gates were introduced.

## Live source audit and final ladder

The original Beach/Ocean 1/Lake 2 routes, WorldLocations authority, contextual economy facade and ownership ladder were inspected before editing. No normal River or Chiqua destination existed. Floater was already reachable at Beach. Lyp's `lyp_item` cash sources existed in the catalog but had no world provider; its separate `lyp` Manillo context permitted Crab only. Salmon existed in authored River 2/3 populations but neither was a normal playable destination. Dorado and Martian Squid were already in playable Lake 2.

| Step | Target | Source type | Exact source ID | Live price / authored fish requirements |
| --- | --- | --- | --- | --- |
| 1 | Baby Frog | `shop_offer` | `shyde_baby_frog` | 250z |
| 2 | Bamboo Rod | `manillo_trade` | `wyndia_bamboo_rod` | Sea Bream x2 |
| 3 | Tail | `manillo_trade` | `wyndia_tail` | Flying Fish x3 |
| 4 | Crab | `manillo_trade` | `lyp_crab` | Black Bass x1, Blue Gill x1, Piranha x1 |
| 5 | Floater | `shop_offer` | `shyde_floater` | 300z |
| 6 | Popper | `shop_offer` | `lyp_popper` | 350z |
| 7 | Angling Rod | `manillo_trade` | `lyp_angling_rod` | Salmon x2, Dorado x2, Martian Squid x2 |
| 8 | Silver Top | `shop_offer` | `lyp_silver_top` | 450z |
| 9 | Hanger | `shop_offer` | `chiqua_hanger` | 600z |

All five new sources have empty authored availability tags (Angling Rod is a trade, not a shop offer). The new purchases' historical offer-resource prices are 20/20/20/80z; runtime canonical resolution supplies 300/350/450/600z. None of these prices or offer/recipe resources were edited. Angling Rod remains unique and non-repeatable. Its exact authored recipe was verified from the live `lyp_angling_rod.tres` and the runtime source API.

The original JSON plan path and ID remain compatible; its targets now contain all nine entries. Completion uses actual rod/lure ownership, including ownership from alternate legitimate sources. It does not depend on obtaining an item from the preferred source, visiting a location, or reaching a recorded playtime. Already-owned later items are naturally skipped. Floater remains purchasable before its place in the recommended ladder.

Acquisition snapshots expose source identity/type, source accessibility, live cash price or authored requirements, owned/missing fish counts, current and reachable populations, and ownership completion. `requirements_reachable` additionally distinguishes an accessible Angling trader from still-locked Salmon water. The existing LIVE guide consumes these snapshots. Locked sources now show a concise locked/unavailable hint rather than telling the player to save money; an accessible trade with unreachable ingredients explicitly reports the fishing-location blocker.

## Normal routes and gates

The normal route graph is now:

```text
Beach <-> Wyndia Ocean 1 <-> Lyp Lake 2 <-> River 2 <-> Chiqua Supply
```

| Destination / provider | Exact unlock condition | Persistent capability |
| --- | --- | --- |
| Ocean 1 / Wyndia | Baby Frog ownership; unchanged | `world.location.wyndia_ocean_outpost` |
| Lake 2 / Lyp | Bamboo Rod and Tail ownership; unchanged | `world.location.lyp_lake_outpost` |
| Lyp Item Shop | Same Lake 2 access; no additional gate | Existing Lake capability |
| Lyp Angling Rod trade | Same Lake 2 access; requires its authored fish to execute | Existing Lake capability |
| River 2 | Crab **and** Floater **and** Popper ownership; must be reached through Lake 2 | `world.location.river_fishing_outpost` |
| Chiqua Supply | Angling Rod **and** Silver Top ownership; must be reached through River 2 | `world.location.chiqua_supply_outpost` |

The existing WorldLocations service latches these capabilities using the existing FishingUnlockState schema. Losing equipment after unlock cannot relock travel. Route traversal still requires each preceding location to be reachable. Crab alone unlocks neither new destination. Angling Rod cannot be required to obtain its own Salmon: River 2 unlocks entirely from earlier lure milestones, and its return path leads back to the already reachable Lyp trader.

Gameplay sequence: buy Floater at Beach, buy Popper at Lyp, interact with the new Lyp `RiverTravel` sign, catch Salmon at River 2 and Dorado/Martian Squid at Lake 2, return to Lyp and trade for Angling Rod, buy Silver Top there, then use River 2's `ChiquaTravel` sign and purchase Hanger from the Chiqua shop. Returns work through the reverse chain to Beach. Travel and shop interactions use the existing deterministic K router; no new competing input handlers were added.

Two normal development scenes were added. Only River 2 adds a previously unavailable fishing population. Chiqua Supply provides a separately gated, legitimate Chiqua economy destination, reusing River 2 fishing rather than duplicating a table or inventing another fishing population. This avoids adding per-merchant progression machinery to the current location architecture. Both scenes inherit the existing shared development rig/environment and carry explicit development labels. The Chiqua seam is not a completed town or a claim about final geography.

## Lyp and Chiqua contextual architecture

Lyp now has two separate visible providers:

- `World/ManilloTrader`: existing `lyp` Manillo policy, explicitly filtered to `lyp_crab` and `lyp_angling_rod`. No cash-shop offers.
- `World/LypItemShop`: new `lyp_item` policy, exposing the authored `lyp_popper` and `lyp_silver_top` purchases. No Manillo trades.

The reusable NPC interaction adapter gained one exported `menu_mode` control. Existing traders default to Fish Trade; the new item-shop scene opens the existing Buy/Sell UI. Both use the same contextual facade and authored sources. No backend transactions were duplicated.

Chiqua Supply's separate provider uses only the authored `chiqua` cash-shop policy: `chiqua_hanger`, `chiqua_toad`, `chiqua_tail`. No Lyp/Wyndia offers or Manillo trades are granted. Existing authored Chiqua companion offers remain intact. Beach and Wyndia policies were not expanded.

River 2 has no merchant context. Its inherited unused trader presentation is hidden, processing disabled, and its blocking collider disabled; QA verifies there is no invisible body left by that stand-in. The current shared shadow implementation and art remain unchanged.

## Angling ingredients and pre-Angling catchability

| Species | All authored populations | Normal population used | Final-run bite weight with Straight at 75% depth |
| --- | --- | --- | --- |
| Salmon | River 2, River 3 | New River 2 outpost | 2.655 |
| Dorado | Lake 2, Lake 3 | Existing Lyp/Lake 2 | 1.944 |
| Martian Squid | Lake 1, Lake 2, Lake 3 | Existing Lyp/Lake 2 | 11.814336 |

River 2's complete existing population is Jellyfish, Trout, Browntail, Rainbow Trout and Salmon. Lake 2's complete existing population is Piranha, Bass, Blue Gill, Black Bass, Martian Squid and Dorado. No population or fish definitions changed. Authored hotspot/ambient resources remain referenced by those populations. Lower bite weights at the tested depth do not make catches guaranteed or efficient; lure/depth choice still matters.

QA uses actual playable scene zones, normal K fishing entry, full authored populations, the actual environment selection context, and the existing selector. It checks required species availability before Angling Rod ownership, commits generated specimens via the existing catch repository, and performs the actual contextual menu trade with exact consumption/reward checks. No debug population override is used to supply these fish. An explicit debug-only River 2 switch at fresh Beach is separately checked and must not count as normal reachability or unlock travel.

Pre-Angling Bamboo Rod plus Straight produces valid live fight contexts and passes the existing average-fish hook/endurance/failure-grace envelope for all three species:

| Species | Fish tier | Recommended rod tier | Bamboo tier | Reference active reel time |
| --- | --- | --- | --- | --- |
| Dorado | 3 | 1 | 1 | 9.03s |
| Martian Squid | 3 | 1 | 1 | 8.36s |
| Salmon | 4 | 2 | 1 | 10.35s |

Salmon's recommendation exceeds Bamboo's tier, but that metadata is descriptive, not a runtime catch lock. Its hook/duration/grace checks pass without changing fight data. This is evidence of an available pre-Angling path; manual Salmon difficulty remains a meaningful playtest item.

These checks do **not** constitute human-played catches or a complete simulated cast/bite/fight/landing sequence. Funding fixtures supply fish to sell, and selected species generate catch-repository specimens after selection. The full existing combat regressions run separately. Rendered presentation and end-to-end manual fishing remain unchecked.

## Simulator decision

Simulator code, purchase assumptions, rates and guardrails were left unchanged. It still schedules Bamboo through `faerie_bamboo_rod` cash purchase at H2.25, whereas normal runtime guidance prefers Wyndia's Sea Bream x2 trade. Runtime now has real route/ingredient access, but QA fixtures and selector checks do not establish player catch rates, travel time, fish-retention choices, failure/lure-loss costs or trading pace. Migrating timed simulator assumptions based on those fixtures would imply pacing evidence we do not have.

No modeled H1/H4/H12 effects were introduced in this pass. The existing source audit/guardrail suite remains 24/24. A future migration should use measured play sessions, compare those checkpoints explicitly, and retain guardrails rather than relaxing them to fit the new model.

## QA commands and results

Executed from the project root with the following executable and script commands (PowerShell output was captured to log files):

```powershell
$godotExe = 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe'
& $godotExe --headless --path . --script res://scripts/qa/world_location_access_qa.gd
& $godotExe --headless --path . --script res://scripts/qa/early_tackle_acquisition_qa.gd
& $godotExe --headless --path . --script res://scripts/qa/world_economy_access_qa.gd
& $godotExe --headless --path . --script res://scripts/qa/world_interaction_qa.gd
& $godotExe --headless --path . --script res://scripts/qa/beach_collision_qa.gd
& $godotExe --headless --path . --script res://scripts/qa/world_character_shadow_qa.gd
git diff --check
```

Each command included a `--log-file` under `C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c/`, with names `economy_v2_world.log`, `economy_v2_acquisition.log`, and `economy_v2_<script-name>.log` for the other suites. Save-writing world QA sets and verifies a unique custom user-data directory before scene bootstrap. Its final run used `C:/Users/Alucard7th/AppData/Roaming/CodexWorldLocationQA-944190`. The normal player save was not used or written by that QA. Standalone acquisition uses a detached memory inventory; economy UI QA overrides both load and save.

| Suite | Final result |
| --- | --- |
| Extended world-location/full-scene QA | 255 checks, 0 failures |
| Extended acquisition QA | 61 checks, 0 failures |
| Contextual economy/menu QA | 81 checks, 0 failures |
| Economy foundation | 13/13 |
| Economy/trade/full-access regressions | 208/208 |
| Simulator source/guardrail regressions | 24/24 |
| Full fishing regression | 22,950/22,950 |
| Campaign loop/director/guide/presentation | 14/14, 14/14, 8/8, 9/9 |
| Fresh-save rehearsal | 55/55 |
| System stability | 27/27 |
| World interaction | 93/93 |
| Beach collision | 65 checks, 0 failures |
| Shared character shadow structural QA | 905 checks, 0 failures |
| Diff whitespace | Clean |

All 17 requested QA categories are covered by the extended acquisition and world suites: new source identities and live prices, exact recipe, reachable species and pre-Angling contexts, debug exclusion, incremental ownership gates and non-circular routes, distinct Lyp policies, Chiqua isolation, actual ownership advancement and alternate ownership, recipe-driven Angling requirement display, travel/reload/persistence and independent full catalog access. An intermediate new fight-context fixture incorrectly supplied a dictionary where the resolver requires FishInstance; that fixture was corrected, without changing production fight code, and the final run is green.

## Complete files changed for this pass

Paths below are relative to `C:/Users/Alucard7th/Documents/FishingGame/fishing_game_clean_candidate_FRESH`.

Modified (9):

```text
actors/locations/LypLakeOutpost.tscn
data/economy/contexts/lyp_outpost.tres
data/progression/early_tackle_acquisition_v1.json
data/world/locations/lyp_lake_outpost.tres
scripts/progression/early_tackle_acquisition.gd
scripts/qa/early_tackle_acquisition_qa.gd
scripts/qa/world_location_access_qa.gd
scripts/world/manillo_trader_npc.gd
scripts/world/world_location_service.gd
```

Added (8):

```text
actors/locations/ChiquaSupplyOutpost.tscn
actors/locations/ContextualItemShopNPC.tscn
actors/locations/RiverFishingOutpost.tscn
data/economy/contexts/chiqua_item_shop.tres
data/economy/contexts/lyp_item_shop.tres
data/world/locations/chiqua_supply_outpost.tres
data/world/locations/river_fishing_outpost.tres
docs/architecture/FIRST_10_HOURS_ECONOMY_GAMEPLAY_V2.md
```

No canonical offer/recipe/fish data, combat, crafting, Triple Triad, shadow code or save schema changed. Existing UI requirement text remains lowercase ASCII `x`.

## Manual Godot verification still required

Walk the complete route and return without QA teleports. Check arrival clearance, travel-sign and NPC label placement, range/facing selection when nearby providers overlap, pause/held-K behavior during purchases and transitions, and purchase/trade visual distinction. Check the Angling row's `3 species` summary and immediate detail panel, including Martian Squid wrapping. Land Salmon with Bamboo and an available lure; also land Dorado/Martian Squid and judge actual difficulty and catch pacing. Restart/reload with the new equipment and confirm guidance and route access. Inspect inherited shadows visually without modifying the shared system.

River and Chiqua still use reused shore/merchant stand-in art, not final river geography, waterfall placement or town content. Final environment/shop art, larger overworld coverage and measured 4–10h pacing remain future work. No rendered visual correctness or measured completion time is claimed.
