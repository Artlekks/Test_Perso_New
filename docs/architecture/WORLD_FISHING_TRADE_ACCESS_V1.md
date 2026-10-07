# World Fishing & Trade Access v1

Implemented and verified headlessly on 2026-10-07 with Godot 4.7.2.stable.official.ed1daf0bf. Rendered presentation and manual fishing fights remain unverified.

## Inspection and scope

Before editing, the only normal playable world was `actors/FishingTestScene_V2.tscn`, the main scene. Its Beach/Ocean 2 fishing context and Beach Merchant were retained. No existing normal travel system or final Wyndia/Lyp/Saldine maps could provide the missing acquisition access. `screen_transition.gd` handles fishing presentation transitions; `fishing_debug_controller.gd` changes fishing spots for debug purposes. Neither represented normal location progression.

The authored Ocean 1 population already includes Sea Bream and Flying Fish; Lake 2 includes all three Crab requirements. Two separate, explicitly named development outposts reuse existing shore assets. Their context identity is separate from the Beach Merchant and from the authored fishing resource's geographical description. These are development trade destinations, not completed towns or a claim that the existing beach is Wyndia/Lyp.

## Shared architecture

`PlayableLocationContext` is an authored resource defining identity, scene path, fishing resource, available economy policies and provider paths, destinations, ownership requirements, and a persisted unlock capability. `WorldLocations` is the single autoload authority for the bound location, progression access, reachable route graph, contextual provider validation, and scene travel.

The scene controller binds the context and assigns the zone's existing fishing resource before child readiness. Normal fishing reads that authoritative context. The existing explicit debug setter remains a separate override and cannot unlock routes or trader policies.

Travel points and traders register with the existing `WorldInteractionRouter`. They add no competing `_input()` handlers. Its existing facing/range, deterministic target selection, echo/held-key handling, modal gating and fishing ownership remain in force. Travel additionally rejects locked destinations, unsupported routes, duplicate pending transitions, paused menus, and active fishing. Context is cleared on exit, arrival and reload. Session inventory and progression services survive scene changes.

Manillo traders reuse the existing economy menu, facade, trade service and authored recipes. An optional recipe allowlist extends `MerchantEconomyContext`: empty retains existing whole-shop behavior, whereas each outpost explicitly permits only its selected recipes. Both listing and execution apply the filter. The trade entry mode uses the existing confirmation transaction flow, defaults to No, displays owned/required fish, and cannot toggle into cash shops. Beach Merchant keeps its original Shyde policy. Debug full catalog access remains explicit and separate.

Acquisition reporting traverses unlocked routes, collecting reachable contexts and populations. It does not require visiting the destination before reporting a source. `available_in_current_spots` and `available_in_reachable_spots` distinguish current water from reachable water. No four-item exception was added to the Campaign Guide.

## Locations, populations and gameplay path

| Location | Authored fishing resource | Complete population | Available economy |
| --- | --- | --- | --- |
| Beach | `data/bof4/spots/ocean_2.tres` | Man O' War, Sea Bass, Flatfish, Octopus, Bonito, Spearfish, Whale | Existing Beach Merchant/Shyde cash shop |
| Wyndia Manillo / Ocean 1 — Development Outpost | `data/bof4/spots/ocean_1.tres` | Man O' War, Flying Fish, Blowfish, Sea Bream | `wyndia_bamboo_rod`, `wyndia_tail` only |
| Lyp Manillo / Lake 2 — Development Outpost | `data/bof4/spots/lake_2.tres` | Piranha, Bass, Blue Gill, Black Bass, Martian Squid, Dorado | `lyp_crab` only |

Normal route:

1. Fish/sell at Beach; buy Baby Frog from the existing Beach Merchant (unchanged 250z offer).
2. Approach the Beach `World/OceanTravel` sign at `(-0.9, 0.06, 0.95)`, face it and press K to reach the ocean outpost.
3. Fish Ocean 1 for Sea Bream ×2 and Flying Fish ×3. Approach the separate Manillo trader and confirm the existing Bamboo Rod and Tail trades.
4. Approach the ocean outpost `World/LakeTravel` sign, face it and press K to reach the lake outpost.
5. Fish Lake 2 for Black Bass ×1, Blue Gill ×1, Piranha ×1; confirm the separate Lyp trader's Crab trade.
6. Return through the lake `ReturnTravel` to the ocean, then its `ReturnTravel` to Beach.

All travel is explicit interaction, not proximity-triggered. The outpost trader is at `(0.9, 0.063, 0.65)`, return sign at `(-1, 0.06, 0.95)`, and ocean-to-lake sign at `(1.5, 0.06, 0.95)`. Travel signs use nonblocking Areas. Existing actor collision and shared shadows are inherited without modifications.

Ocean access unlocks on Baby Frog ownership; Lake access unlocks on Bamboo Rod **and** Tail ownership. These are equipment milestones, not elapsed-time checks. They latch into the existing `FishingUnlockState` flags `world.location.wyndia_ocean_outpost` and `world.location.lyp_lake_outpost`. Losing a lure afterward cannot strand the player by relocking a return route. Existing inventory/unlock persistence is reused; no save schema or persistent current-location field was added. Application restart begins at the original Beach; scene reload reconstructs that scene's own location context.

Resulting reachability: initially Baby Frog only; Baby Frog unlocks the reachable Ocean 1/Wyndia Bamboo and Tail sources; ownership of both rewards unlocks Lake 2/Lyp Crab; completing that trade completes the existing early acquisition spine.

## Catchability evidence and limits

The executable location QA enters fishing with real K input in each outpost's authored shore zone. It uses the scene's actual selector, full normal population, starter Straight lure, 75% of the zone's water depth, and the actual environment selection context. It selects each required species without the debug population override and verifies a positive bite weight. Final-run weights:

| Species | Spot | Effective weight |
| --- | --- | --- |
| Sea Bream | Ocean 1 | 17.769963671313 |
| Flying Fish | Ocean 1 | 31.9987341020041 |
| Black Bass | Lake 2 | 18.87012 |
| Blue Gill | Lake 2 | 16.736976 |
| Piranha | Lake 2 | 21.8784 |

The ocean weights vary slightly with the live environment clock. These values demonstrate nonzero availability under normal selection conditions, not guaranteed catches on every cast. QA then generates specimens using each selected authored species, calls the existing catch repository, and trades the resulting inventory through the existing menu confirmation/backend transaction. It does **not** simulate complete rod/cast/bite/fight/landing sequences for these species or demonstrate a human-played fishing fight. Existing combat regressions pass separately. Beach funding is a fixture of four Sea Bass sold through the existing facade, not four manually caught fish.

## Executable QA and results

Executable used:

```powershell
$godotExe = 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe'
$qaLogs = 'C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c'
& $godotExe --headless --path . --log-file "$qaLogs/world_location_access_qa.log" --script res://scripts/qa/world_location_access_qa.gd
& $godotExe --headless --path . --log-file "$qaLogs/world_economy_access_qa_final.log" --script res://scripts/qa/world_economy_access_qa.gd
& $godotExe --headless --path . --log-file "$qaLogs/early_tackle_acquisition_qa_final.log" --script res://scripts/qa/early_tackle_acquisition_qa.gd
& $godotExe --headless --path . --log-file "$qaLogs/world_interaction_qa.log" --script res://scripts/qa/world_interaction_qa.gd
& $godotExe --headless --path . --log-file "$qaLogs/beach_collision_qa.log" --script res://scripts/qa/beach_collision_qa.gd
& $godotExe --headless --path . --log-file "$qaLogs/world_character_shadow_qa.log" --script res://scripts/qa/world_character_shadow_qa.gd
git diff --check
```

These commands were executed from the project root; output was captured/filtered in PowerShell. The final location run used `C:/Users/Alucard7th/AppData/Roaming/CodexWorldLocationQA-929876`. Each run sets and verifies a fresh disposable custom user directory **before** gameplay bootstrap. It refuses to proceed if isolation setup fails. Existing standalone economy/acquisition QA uses memory inventories. Normal player save files were not used or written.

| Suite | Result |
| --- | --- |
| New location access QA; all 18 requested categories | 113 checks, 0 failures |
| Full existing fishing regression, invoked by location QA | 22,950/22,950 |
| World economy access | 45 checks, 0 failures |
| Existing economy foundation | 13/13 |
| Existing economy/trade/full-access groups | 208/208 |
| Existing economy progression simulator guardrails | 24/24 |
| Early tackle acquisition | 48 checks, 0 failures |
| Campaign loop / director / guide / presentation | 14/14, 14/14, 8/8, 9/9 |
| Fresh-save rehearsal, invoked from isolated scene bootstrap | 55/55 |
| System stability, invoked from isolated scene bootstrap | 27/27 |
| World interaction | 93 checks, 0 failures |
| Beach collision | 65 checks, 0 failures |
| Shared character shadow structural QA | 905 checks, 0 failures |
| Diff whitespace check | Clean |

The location suite exercises locked travel, K-router/physics targeting, duplicate transitions, active-fishing and modal exclusion, exact trader recipe filters and denied unrelated offers, confirmation/consumption/rewards, debug isolation, context clearing, scene reload, return routes, ownership reload, and persisted unlock flags after equipment loss. It explicitly checks that reachable Ocean species are not mislabeled as available at the current Beach.

The initial full fishing harness produced 22,947/22,950: three shore-boundary fixture assertions used global transforms on nodes outside the SceneTree. The fixture now attaches its nodes to a temporary real world and supplies the expected RippleView child. Original assertions were retained; gameplay shore code was not changed. After that QA-only fixture correction the complete harness passes. Canonical prices, recipes, species, combat, crafting, Triple Triad, shadows and simulator guardrails were not edited.

## Complete file manifest

Paths below are relative to `C:/Users/Alucard7th/Documents/FishingGame/fishing_game_clean_candidate_FRESH`. Ten existing files changed; twenty-two files added (including this report and five Godot script UID sidecars).

Modified:

```text
actors/FishingTestScene_V2.tscn
project.godot
scripts/economy/merchant_economy_context.gd
scripts/fish_zone_v2.gd
scripts/fishing_economy_access.gd
scripts/fishing_economy_menu.gd
scripts/fishing_regression_harness.gd
scripts/fishing_session_services.gd
scripts/progression/early_tackle_acquisition.gd
scripts/progression/playable_campaign_progression_director.gd
```

Added:

```text
actors/locations/DevelopmentFishingOutpost.tscn
actors/locations/LocationTravelPoint.tscn
actors/locations/LypLakeOutpost.tscn
actors/locations/ManilloTraderNPC.tscn
actors/locations/WyndiaOceanOutpost.tscn
data/economy/contexts/lyp_outpost.tres
data/economy/contexts/wyndia_outpost.tres
data/world/locations/beach.tres
data/world/locations/lyp_lake_outpost.tres
data/world/locations/wyndia_ocean_outpost.tres
docs/architecture/WORLD_FISHING_TRADE_ACCESS_V1.md
scripts/qa/world_location_access_qa.gd
scripts/world/location_travel_point.gd
scripts/world/location_travel_point.gd.uid
scripts/world/manillo_trader_npc.gd
scripts/world/manillo_trader_npc.gd.uid
scripts/world/playable_location_context.gd
scripts/world/playable_location_context.gd.uid
scripts/world/playable_location_scene.gd
scripts/world/playable_location_scene.gd.uid
scripts/world/world_location_service.gd
scripts/world/world_location_service.gd.uid
```

## Remaining visual/content work

Both outposts use a shared development fishing rig/environment template copied from the existing working scene; the lake still has temporary beach-like shoreline art. Their trader reuses merchant art as a clearly labeled separate Manillo stand-in. Final town geography, lake art, destination arrivals, trader art and travel-sign polish remain future content. Other towns, other authored fishing locations, and unrelated Wyndia/Lyp trade offers are deliberately unavailable through these new normal routes. This is not a complete overworld or whole-project audit.

In rendered Godot, verify travel-sign readability and obstruction, walking approach/range/facing, destination arrival clearance, lake placeholder identity, trade header/row/info/confirmation layout, pause/unpause, rapid and held K during menus and transitions, fish visibility and complete landing of the five required species, return routes, scene reload, and shared shadows beneath the inherited trader. No rendered visual correctness is claimed.
