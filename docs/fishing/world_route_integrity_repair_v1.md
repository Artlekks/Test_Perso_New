# World Route Integrity Repair v1

Validated with Godot 4.7.2.stable.official.ed1daf0bf on 2026-10-07. This pass restores route data and strengthens QA. Prices, recipes, fish balance, acquisition order, simulator targets and all 24 guardrails are unchanged. The preceding uncommitted reconciliation implementation is preserved.

## Metadata-loss evidence

`git show 98750f0 -- data/world/locations/lyp_lake_outpost.tres data/economy/contexts/lyp_outpost.tres` identifies the exact deletion. Commit `98750f0` ("fixed camera behavior when fishing") replaced the Lyp resource's older text representation with a UID-bearing, typed-array representation and removed four authored properties: `economy_provider_paths`, `destinations`, `required_lure_ids`, `required_rod_ids`. It also introduced `shop_ids = null` in the trade-only Lyp context. The preceding gameplay commit `b96dec1` contains the intended values restored here.

This is a partial resource rewrite/data-loss regression in that commit, not a duplicate location, wrong UID, missing PackedScene, new progression design or a simulator pricing problem. The serialization-style format change is visible in Git; Git cannot prove which editor/tool operation discarded the properties or why its in-memory values were empty. Current Godot round-trip checks preserve all four arrays, so this evidence does not establish an ongoing ResourceSaver defect.

The service's empty-array defaults then made Lake unlocked without Bamboo/Tail, provided zero contextual economy sources, and gave Lake no outbound routes. The current scenes still contained both providers and both travel signs, but WorldLocations correctly denied providers absent from the authored mapping. That stranded the normal acquisition route.

Only one authored resource declares `lyp_lake_outpost`; its UID `uid://xeoksoafty1u` and the Lyp trade context UID `uid://46s7caaqg333` resolve to their stated files. No UID was regenerated. External references in all five location resources, their playable scenes and their economy contexts resolve correctly. Loading/instantiating the inherited scenes emitted no invalid-UID warnings.

## Restored route and provider ownership

| Destination | Existing ownership gate | Existing persistent flag |
|---|---|---|
| Ocean / `wyndia_ocean_outpost` | `baby_frog` | `world.location.wyndia_ocean_outpost` |
| Lake / `lyp_lake_outpost` | `bamboo_rod` + `tail` | `world.location.lyp_lake_outpost` |
| River / `river_fishing_outpost` | `crab` + `floater` + `popper` | `world.location.river_fishing_outpost` |
| Chiqua / `chiqua_supply_outpost` | `angling_rod` + `silver_top` | `world.location.chiqua_supply_outpost` |

Lake's restored destinations are exactly `PackedStringArray("wyndia_ocean_outpost", "river_fishing_outpost")`. Its restored provider array is exactly `PackedStringArray("World/ManilloTrader", "World/LypItemShop")`, corresponding in order to the existing `lyp_outpost` and `lyp_item_shop` contexts. The redundant null `shop_ids` override was removed so the trade context uses its existing empty PackedStringArray default.

`World/ManilloTrader` exposes `lyp_crab` and `lyp_angling_rod`; `World/LypItemShop` exposes `lyp_popper` and `lyp_silver_top`. They remain separate contexts. Ocean, River and Chiqua metadata already matched the prior design and were not edited.

The normal route is Beach -> Ocean -> Lake -> River -> Chiqua, with Chiqua -> River -> Lake -> Ocean -> Beach return signs. No debug destination, fallback, elapsed-time gate or automatic gameplay item grant was added.

## Null-scene root cause and QA repair

An isolated reproduction reinstated only the four missing arrays in memory. At process frame 34 the original QA had completed normal Ocean fishing entry/exit and still had `WyndiaOceanOutpost` as `current_scene`. Its next assertion was `check(not locations.request_travel(&"lyp_lake_outpost").success, "lake remains locked after arrival")`. With Lake's gate erased, that negative probe actually succeeded and called `change_scene_to_file`. Godot immediately removed the current scene and set `current_scene` to null until the deferred new-scene installation. The synchronous catch/menu assertions then called `get_node`/`find_child` on null. This happened before the frame timeout; it was not a missing scene file or shutdown-only artifact.

Restoring the ownership gate prevents the unintended transition. QA additionally pins all five sets of prerequisites, flags, directed routes, provider order, actual scene/context identity, provider binding, reciprocal travel signs, referenced paths and explicit UIDs. Failed structural checks now stop and clean up before negative gameplay travel probes. Actual travel/reload waits use `scene_changed`, then two process frames, instead of assuming eight frames guarantee scene readiness. Default QA retains every existing campaign/fresh-save/fishing regression assertion. `--architecture-only` runs the complete route/acquisition integration first and skips only the final aggregate regression stage; startup campaign/fresh-save health failures are still logged and remain failures in the default full run.

The injected-data-loss rerun now exits 1 with 12 explicit structural failures and no script/null-scene errors. No temporary diagnostic code was added to the project; reproduction tooling/logs live only in the external artifacts directory.

## Runtime acquisition evidence

The scene integration traversed every forward/return route and reloaded Lake and Chiqua. It opened contextual providers through routed K, confirmed real menu transactions, checked consumption and shop/trade isolation, and checked context clearing across travel/reload. QA funding/catches use isolated fixtures: required species are selected from each real population through FishSelector and committed through the catch repository. This proves structural acquisition access, not a rendered human nine-step playthrough or actual elapsed-hour pacing.

All nine sources are reachable: Baby Frog (Beach), Bamboo/Tail (Ocean Manillo), Crab (Lyp Manillo), Floater (Beach), Popper (Lyp shop), Angling (Lyp Manillo using River Salmon and Lake Dorado/Martian Squid), Silver Top (Lyp shop), Hanger (Chiqua shop). The same authored Bamboo loadout resolves valid Salmon/Dorado/Squid fight contexts before Angling is owned.

## Post-repair simulator results

These are deterministic expected-value simulations, not measured play times. Existing hourly purchase eligibility and catch-rate assumptions remain unchanged. Both profiles acquire Baby Frog at H0.75, Bamboo H2.25, Tail H3, Crab H3.5, Floater H5, Popper H6, Angling H7.25, Silver Top H8 and Hanger H9. Angling misses the unchanged H7 target by one simulation step because its fish reservation becomes payable at H7.25.

| Profile | Checkpoint | Zenny | Catches | Sold | Traded fish | Species | Cards | Rods | Lures | Bait remaining |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Balanced | H1 | 1408 | 20 | 9 | 0 | 5 | 7 | 1 | 2 | 3 |
| Balanced | H4 | 2442 | 56 | 24 | 8 | 12 | 15 | 2 | 4 | 1 |
| Balanced | H10 | 6881 | 134 | 62 | 14 | 21 | 27 | 3 | 8 | 1 |
| Balanced | H12 | 10537 | 160 | 76 | 14 | 21 | 31 | 3 | 8 | 1 |
| Sell-heavy | H1 | 2307 | 20 | 14 | 0 | 5 | 6 | 1 | 2 | 2 |
| Sell-heavy | H4 | 4373 | 56 | 38 | 8 | 11 | 11 | 2 | 4 | 0 |
| Sell-heavy | H10 | 14464 | 134 | 98 | 14 | 19 | 17 | 3 | 8 | 0 |
| Sell-heavy | H12 | 20975 | 160 | 120 | 14 | 21 | 19 | 3 | 8 | 0 |

Route audit issues: zero. Nine-step viability: passes. Invariant QA: 177/177. Existing guardrails: **22/24**, improved from 19/24 before route repair. Remaining failures are Balanced H12 cash 10537 > 8000 and Sell-heavy H12 cash 20975 > 15500. No ceilings or prices were changed to hide these failures. Required trade fish are reserved before discretionary sales; all 14 recipe fish are consumed exactly once and species accounting remains conserved.

## Commands and actual results

Executable used below: `C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe`.

Artifact directory `A`: `C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c`.

Each Godot command ran from the current project with `--headless --path . --quit-after 1800 --log-file A/<log> --script <script>`, plus the user arguments shown below. All gameplay-bootstrap runs isolate userdata; the wrappers only configure that isolation before invoking the existing suites. No normal save was used.

| Script / arguments | Log | Actual result |
|---|---|---|
| `res://scripts/qa/world_location_access_qa.gd -- --architecture-only` | `route-architecture-final.log` | 566/566 architecture/integration checks; exit 0. Startup aggregate economy failures still logged. |
| `res://scripts/qa/world_location_access_qa.gd` | `route-final-world.log` | 571/573 total; exit 1. Only aggregate campaign and fresh-save health checks fail. All 566 architecture checks pass. |
| `A/world_economy_access_qa_isolated.gd` | `route-final-economy.log` | Contextual economy 80/81; exit 1 solely simulator-health assertion. Economy Foundation 13/13; economy/trade/full-access groups 208/208. |
| `A/early_tackle_acquisition_qa_isolated.gd` | `route-final-acquisition.log` | 60/61; exit 1 solely aggregate campaign health. |
| `res://scripts/qa/runtime_economy_reconciliation_qa.gd -- --report=A/economy-post-route-repair.json` | `route-final-reconciliation.log` | 177/177 invariant checks, exit 0; separately reports 22/24 guardrails, nine-step viability PASS, no route issues. |
| `res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions` | `route-final-fishing.log` | Fight camera 120/120, full fishing 22950/22950, exit 0. Fight 24/24; Fishing Presentation 10/10; Stability 27/27. |
| `git diff --check` | console | Exit 0, no whitespace errors. |

Campaign and fresh-save suites actually executed through session initialization and the full location integration's `_run_regressions`, plus the acquisition suite: Campaign Loop 13/14 (aggregate simulator-health failure); Director 14/14; Guide 8/8; Campaign Presentation 9/9; Fresh Save Rehearsal 54/55 (campaign-green dependency failure). These are not claimed green.

The diagnostic reproduction used `--quit-after 600 --script A/route_loss_reproduction.gd`; `route-loss-reproduction.log` captures the original null-scene cascade. The final rerun is `route-loss-failfast.log`, exit 1 with the intended malformed-metadata failures and no null/script errors. Repaired final logs contain no invalid-UID warnings or script errors. Existing Triple Triad precomposition QA emits its expected backend-not-ready warning while its suite passes 101/101.

## Files for this repair

- `data/world/locations/lyp_lake_outpost.tres`: restores the four exact authored arrays.
- `data/economy/contexts/lyp_outpost.tres`: removes the corrupted null override; trade policy unchanged.
- `scripts/qa/world_location_access_qa.gd`: exact integrity checks, failed-architecture cleanup, scene-change waits and explicit architecture reporting.
- `docs/fishing/world_route_integrity_repair_v1.md`: this evidence/results report.

The prior six reconciliation files remain uncommitted and unchanged by this repair: `scripts/progression/economy_progression_simulator.gd`, `scripts/progression/economy_runtime_route.gd` and its `.uid`, `scripts/qa/runtime_economy_reconciliation_qa.gd` and its `.uid`, `docs/fishing/runtime_economy_reconciliation_v1.md`.

Still outstanding: the two unchanged economy cash-ceiling failures and rendered fresh-save pacing/play-feel validation. This repair proves route integrity and structural acquisition access; it does not certify full economy QA green or visual correctness.
