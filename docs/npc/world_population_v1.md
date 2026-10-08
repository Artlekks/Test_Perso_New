# NPC World Population v1

36 visuals reviewed for provisional casting; 17 have existing authored or reviewed directional/action semantics. The other 19 retain explicitly unreviewed pose/action semantics. No special-reference identity can be proved: small bird and feathered traveler are distinct candidates, several hats/robes exist, and reference ordering is unavailable. Teleporter Guardian and all three Master mappings remain **UNCONFIRMED**. No IDs renamed; no mastery/teleport gameplay installed.

Ocean/Wyndia and Lake/Lyp each have one physical outpost, not separate town scenes. 13 new stationary visual placeholders; 23 catalogue entries receive no new placement. Original merchant/crafter/captain/master/crab providers and their reused art remain untouched; no functional visuals replaced.

## Actual placements

| Location | Catalogue ID | Development role | Functional? | Movement | Notes |
|---|---|---|---|---|---|
| beach | placeholder_14bf342a | angler | No; ambient visual placeholder | Stationary | World/PopulationAngler at [-2.45, 0, 1.1] |
| beach | placeholder_cac2bbc2 | traveler, ambient_citizen | No; ambient visual placeholder | Stationary | World/PopulationResident at [2.45, 0, 1.1] |
| wyndia_ocean_outpost | placeholder_68024840 | harbor_worker | No; ambient visual placeholder | Stationary | World/PopulationHarborWorker at [-2.4, 0, 0.15] |
| wyndia_ocean_outpost | placeholder_78f1768c | angler | No; ambient visual placeholder | Stationary | World/PopulationAngler at [2.5, 0, 0.15] |
| wyndia_ocean_outpost | placeholder_8c3ae570 | harbor_worker | No; ambient visual placeholder | Stationary | World/PopulationHarborResident at [-2.4, 0, 1.05] |
| lyp_lake_outpost | placeholder_21f7b2b2 | seated_angler | No; ambient visual placeholder | Stationary | World/PopulationSeatedAngler at [-2.5, 0, 0.15] |
| lyp_lake_outpost | placeholder_d1282736 | veteran_angler | No; ambient visual placeholder | Stationary | World/PopulationVeteranAngler at [2.5, 0, 0.15] |
| lyp_lake_outpost | placeholder_e1466c4f | elder | No; ambient visual placeholder | Stationary | World/PopulationElder at [-2.5, 0, 1.05] |
| river_fishing_outpost | placeholder_9d2e2d78 | traveler, quest_placeholder | No; ambient visual placeholder | Stationary | World/PopulationUnusualTraveler at [-2.4, 0, 0.15] |
| river_fishing_outpost | placeholder_6d89ee8e | ambient_creature | No; ambient visual placeholder | Stationary | World/PopulationAmbientBird at [2.5, 0, 0.35] |
| chiqua_supply_outpost | placeholder_3cb9da3b | trader, special_vendor | No; ambient visual placeholder | Stationary | World/PopulationTrader at [-2.4, 0, 0.15] |
| chiqua_supply_outpost | placeholder_43fb177f | quest_placeholder, traveler | No; ambient visual placeholder | Stationary | World/PopulationUnusualResident at [2.5, 0, 0.15] |
| chiqua_supply_outpost | placeholder_d7c2eeb9 | mystic, quest_placeholder | No; ambient visual placeholder | Stationary | World/PopulationMystic at [-2.4, 0, 1.05] |

## Complete catalogue audit

Reuse below is direct SpriteFrames usage in existing actor scenes (including provider base scenes); these are preserved, not additional placements. Directions/animation semantics are not inferred from unlabeled pose strips. Role tags in visual profiles remain original compatibility metadata; provisional casting lives separately on NPCCatalogEntry. Width/depth/opacity/grounding use the existing families unchanged.

| ID | Appearance | Directions | Animations | Movement capability | Collider | Shadow | Existing visual tags | Existing scene reuse | Tier | Provisional roles | Art status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| crab_small_01 | Small Crab | ("S", "SE", "E", "NE", "N", "NW", "W", "SW") | idle_e, idle_n, idle_ne, idle_nw, idle_s, idle_se, idle_sw, idle_w, walk_nw, walk_sw | false | ambient_creature | critter | ("ambient_creature") | BeachFishingCritter: two existing roaming crabs | C | ambient_creature | EXISTING_AUTHORED |
| creature_green_01 | Green Small Creature | ("S", "SE", "E", "NE", "N") | green_e, green_n, green_ne, green_s, green_se, red_e, red_n, red_ne, red_s, red_se | false | ambient_creature | critter | ("ambient_creature") | None (catalogue only) | C | ambient_creature | EXISTING_AUTHORED |
| creature_red_01 | Red Small Creature | ("S", "SE", "E", "NE", "N") | green_e, green_n, green_ne, green_s, green_se, red_e, red_n, red_ne, red_s, red_se | false | ambient_creature | critter | ("ambient_creature") | None (catalogue only) | C | ambient_creature | EXISTING_AUTHORED |
| fisher_captain_01 | Fishing Captain | ("SE", "SW", "NE", "NW") | idle_ne, idle_nw, idle_se, idle_sw, smoke, walk_ne, walk_nw, walk_se, walk_sw | true | humanoid_standard | humanoid_standard | ("fisher", "card_opponent") | FishingCardMakerNPC (existing provider) | B | angler,card_opponent | EXISTING_AUTHORED |
| merchant_heavy_01 | Heavy Merchant | ("one view") | Bag_Search, Stand_Interest | false | humanoid_heavy | humanoid_standard | ("merchant", "special_vendor") | BeachMerchantNPC (existing provider) | B | merchant,special_vendor | EXISTING_AUTHORED |
| placeholder_14bf342a | Rod Angler | ("UNCONFIRMED") | pose_000, pose_001 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | angler | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_21f7b2b2 | Seated Angler | ("UNCONFIRMED") | pose_000, pose_001, pose_002, pose_003, pose_004, pose_005, pose_006, pose_007, pose_008, pose_009, pose_010, pose_011, pose_012, pose_013, pose_014, pose_015, pose_016, pose_017, pose_018, pose_019, pose_020, pose_021, pose_022, pose_023, pose_024, pose_025, pose_026 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | seated_angler | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_3cb9da3b | Turban Trader | ("N", "NE", "E", "SE", "S") | idle_n, idle_ne, idle_e, idle_se, idle_s, walk_ne, walk_se | true | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | A | trader,special_vendor | REVIEWED_DIRECTIONS |
| placeholder_43fb177f | Horned Traveler | ("N", "NE", "E", "SE", "S") | idle_n, idle_ne, idle_e, idle_se, idle_s, walk_ne, walk_se | true | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | A | quest_placeholder,traveler | REVIEWED_DIRECTIONS |
| placeholder_4b58ab5e | Blue Scarf Traveler | ("UNCONFIRMED") | pose_000, pose_001 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | C | traveler | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_68024840 | Lanky Worker | ("UNCONFIRMED") | pose_000, pose_001 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | C | harbor_worker | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_6d89ee8e | Small Bird | ("N", "NE", "E", "SE", "S") | idle_n, idle_ne, idle_e, idle_se, idle_s, fly_ne, fly_se | false | ambient_creature | critter | ("placeholder", "role_unconfirmed") | None (catalogue only) | C | ambient_creature | REVIEWED_DIRECTIONS |
| placeholder_78f1768c | Brown Hat Traveler | ("N", "NE", "E", "SE", "S") | idle_n, idle_ne, idle_e, idle_se, idle_s, walk_ne, walk_se | true | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | angler | REVIEWED_DIRECTIONS |
| placeholder_7d53dc6e | Violet Armored Traveler | ("N", "NE", "E", "SE", "S") | idle_n, idle_ne, idle_e, idle_se, idle_s, walk_ne, walk_se | true | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | guard | REVIEWED_DIRECTIONS |
| placeholder_7f1b19bc | Blue Cap Stout Traveler | ("UNCONFIRMED") | pose_000, pose_001 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | trader | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_837b6a03 | Short Robed Traveler | ("UNCONFIRMED") | pose_000, pose_001, pose_002, pose_003, pose_004, pose_005, pose_006, pose_007, pose_008, pose_009, pose_010, pose_011 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | C | ambient_citizen | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_8483df78 | Angler Action Sheet | ("UNCONFIRMED") | pose_000, pose_001, pose_002, pose_003, pose_004, pose_005, pose_006, pose_007, pose_008, pose_009, pose_010, pose_011, pose_012, pose_013, pose_014, pose_015, pose_016, pose_017, pose_018, pose_019, pose_020, pose_021, pose_022, pose_023, pose_024, pose_025, pose_026, pose_027, pose_028, pose_029, pose_030, pose_031, pose_032, pose_033, pose_034, pose_035, pose_036, pose_037, pose_038, pose_039, pose_040, pose_041, pose_042, pose_043, pose_044, pose_045, pose_046, pose_047, pose_048, pose_049, pose_050, pose_051, pose_052, pose_053, pose_054, pose_055, pose_056, pose_057, pose_058, pose_059, pose_060, pose_061 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | angler | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_85f413fb | Red Vest Seated Traveler | ("UNCONFIRMED") | pose_000, pose_001, pose_002, pose_003, pose_004, pose_005, pose_006, pose_007, pose_008, pose_009, pose_010, pose_011, pose_012, pose_013, pose_014, pose_015, pose_016, pose_017, pose_018, pose_019, pose_020, pose_021, pose_022, pose_023, pose_024, pose_025, pose_026, pose_027 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | C | ambient_citizen | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_8c3ae570 | Tall Hat Green Traveler | ("N", "NE", "E", "SE", "S") | idle_n, idle_ne, idle_e, idle_se, idle_s, walk_ne, walk_se | true | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | harbor_worker | REVIEWED_DIRECTIONS |
| placeholder_9d2e2d78 | Feathered Traveler | ("N", "NE", "E", "SE", "S") | idle_n, idle_ne, idle_e, idle_se, idle_s, walk_ne, walk_se | true | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | A | traveler,quest_placeholder | REVIEWED_DIRECTIONS |
| placeholder_c3997e38 | Gold Armored Stout Traveler | ("UNCONFIRMED") | pose_000, pose_001, pose_002, pose_003, pose_004 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | A | special_vendor | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_cac2bbc2 | Red Hair Traveler | ("N", "NE", "E", "SE", "S") | idle_n, idle_ne, idle_e, idle_se, idle_s, walk_ne, walk_se | true | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | C | traveler,ambient_citizen | REVIEWED_DIRECTIONS |
| placeholder_d1282736 | Dark Hat Traveler | ("N", "NE", "E", "SE", "S") | idle_n, idle_ne, idle_e, idle_se, idle_s, walk_ne, walk_se | true | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | veteran_angler | REVIEWED_DIRECTIONS |
| placeholder_d7c2eeb9 | Purple Robed Traveler | ("UNCONFIRMED") | pose_000, pose_001 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | A | mystic,quest_placeholder | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_e1466c4f | Green Bearded Traveler | ("UNCONFIRMED") | pose_000, pose_001 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | elder | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_e5085f21 | Seated Fishing Pose | ("UNCONFIRMED") | pose_000, pose_001, pose_002, pose_003, pose_004, pose_005, pose_006, pose_007, pose_008, pose_009 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | seated_angler | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_e8e1ac56 | Green Cap Trader | ("UNCONFIRMED") | pose_000, pose_001, pose_002, pose_003, pose_004, pose_005, pose_006, pose_007, pose_008, pose_009, pose_010, pose_011, pose_012, pose_013, pose_014, pose_015, pose_016, pose_017, pose_018, pose_019, pose_020, pose_021, pose_022, pose_023, pose_024, pose_025, pose_026, pose_027, pose_028, pose_029, pose_030, pose_031, pose_032, pose_033, pose_034, pose_035, pose_036, pose_037, pose_038, pose_039, pose_040, pose_041, pose_042 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | trader | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_ea87e795 | Red Cap Stout Traveler | ("UNCONFIRMED") | pose_000, pose_001, pose_002, pose_003, pose_004, pose_005, pose_006, pose_007, pose_008, pose_009, pose_010, pose_011, pose_012, pose_013, pose_014, pose_015 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | C | ambient_citizen | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_f3876069 | Pale Hood Traveler | ("UNCONFIRMED") | pose_000, pose_001 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | veteran_angler | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_f8644d09 | Purple Cape Stout Traveler | ("UNCONFIRMED") | pose_000, pose_001, pose_002, pose_003, pose_004 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | A | mystic | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_faacbedb | Seated Light Angler | ("UNCONFIRMED") | pose_000, pose_001, pose_002, pose_003, pose_004, pose_005, pose_006, pose_007, pose_008, pose_009, pose_010, pose_011, pose_012, pose_013, pose_014, pose_015, pose_016, pose_017, pose_018, pose_019, pose_020, pose_021, pose_022, pose_023, pose_024, pose_025, pose_026, pose_027, pose_028, pose_029, pose_030, pose_031, pose_032, pose_033, pose_034, pose_035, pose_036, pose_037, pose_038, pose_039 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | seated_angler | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_ff1c0303 | Green Turban Traveler | ("N", "NE", "E", "SE", "S") | idle_n, idle_ne, idle_e, idle_se, idle_s, walk_ne, walk_se | true | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | trader | REVIEWED_DIRECTIONS |
| placeholder_ff6dba97_blue | Stout Bearded Traveler (blue) | ("UNCONFIRMED") | pose_000, pose_001, pose_002, pose_003, pose_004, pose_005, pose_006, pose_007 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | B | elder | POSES_NEED_SEMANTIC_REVIEW |
| placeholder_ff6dba97_orange | Stout Bearded Traveler (orange) | ("UNCONFIRMED") | pose_008, pose_009, pose_010, pose_011, pose_012, pose_013, pose_014, pose_015 | false | humanoid_standard | humanoid_standard | ("placeholder", "role_unconfirmed") | None (catalogue only) | C | ambient_citizen | POSES_NEED_SEMANTIC_REVIEW |
| seated_crafter_01 | Seated Crafter | ("one view") | Idle | false | seated_npc | humanoid_standard | ("harbor_worker", "quest_placeholder") | BeachCrafterNPC (existing provider) | B | crafter,harbor_worker | EXISTING_AUTHORED |
| smoking_traveler_01 | Smoking Traveler | ("one view") | Idle | false | seated_npc | humanoid_standard | ("traveler", "quest_placeholder") | FishingMasterStillWaterNPC (existing provider) | B | veteran_angler,traveler | EXISTING_AUTHORED |

## Reserved catalogue entries

18 visuals remain unused/reserved: creature_green_01, creature_red_01, placeholder_4b58ab5e, placeholder_7d53dc6e, placeholder_7f1b19bc, placeholder_837b6a03, placeholder_8483df78, placeholder_85f413fb, placeholder_c3997e38, placeholder_e5085f21, placeholder_e8e1ac56, placeholder_ea87e795, placeholder_f3876069, placeholder_f8644d09, placeholder_faacbedb, placeholder_ff1c0303, placeholder_ff6dba97_blue, placeholder_ff6dba97_orange.

13 unique catalogue visuals are newly placed. Five other visuals already serve existing functional actors/roaming crabs, so 18 unique catalogue visuals are represented overall. 23 receive no new instance, including those five preserved visuals. Existing Triple Triad opponents and all other provider scenes remain preserved too; source-file reuse is reported above rather than counted as a new catalogue placement.

Static pose sheets may be placed without asserting walk timing or back views. No new patrols, bespoke colliders, shadow offsets, dialogue/economy providers or input handlers. Catalogue role/tier metadata is persisted in data/npc/world_population_v1.json and emitted by the existing ingestion helper. Preview groups A/B/C and labels semantic art status; still development-only.

## Acceptance

QA results are recorded below after running actual scene/physics tests. Visual acceptance on iPhone is still required after refresh: check silhouettes, spacing, ground contact and crowded access points.

## Executed verification

Godot executable: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`. Commands below ran with the project as working directory. Native launches used `Start-Process -WindowStyle Hidden -Wait -PassThru` and wrote `build/population-*.log`; each command had a corresponding `--log-file` argument.

| Command arguments | Actual result |
|---|---|
| `--path . --script scripts/qa/npc_world_population_qa.gd -- --rendered` | 449/449; exit 0; all 5 worlds rendered; each of 12 hard actors stopped against a resolving player over 120 physics ticks, maximum passive displacement 0.0, epsilon 0.00001 |
| `--path . --script scripts/qa/npc_catalog_qa.gd -- --rendered` | 2375/2375; exit 0; tier-labelled all-36 preview captured |
| `--headless --path . --script scripts/qa/world_location_access_qa.gd` | 586/586; exit 0; rerun after final Beach positions; actual travel/acquisition/interaction probes |
| `--headless --path . --script scripts/qa/world_interaction_qa.gd` | 93/93; exit 0 |
| `--headless --path . --script scripts/qa/world_actor_collision_qa.gd` | 96/96; exit 0; passive displacement 0.0 |
| `--headless --path . --script scripts/qa/world_grounding_standard_qa.gd` | 1039/1051; exit 1; the same 12 known gathering InteractionArea shape baseline mismatches remain visible; no new grounding failures |
| `--headless --path . --script scripts/qa/world_presentation_tuning_qa.gd` | 265/265; exit 0 |
| `--headless --path . --script scripts/qa/world_economy_access_qa.gd -- --structural-only` | 81/81; exit 0; foundation 13/13; trade/full-access groups 208/208; economy targets still 22/24 (Sell-heavy H12 20975 > 15500; Balanced H12 10537 > 8000) |
| `--headless --path . --script scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions` | camera 120/120 and full fishing 22950/22950; exit 0; campaign loop 14/14, fresh save 55/55, fight 24/24, presentation 10/10, stability 27/27 |

`python -m py_compile tools/npc/build_npc_catalog.py`: PASS. `git diff --check`: PASS (existing CRLF normalization advisories only). An initial population probe caught a too-close Beach placement and an overly broad travel-provider uniqueness check; both were corrected and the final rendered suite passed.

Rendered captures: `build/population-captures/*.png` and `build/npc-captures/*.png`, inspected locally. Native Vulkan rendering logged the existing `shader_rd.cpp:696 f.is_null()` shader-cache write error five times; these engine diagnostics are retained, not suppressed. No population QA assertions failed in the final run. Desktop overview captures do not establish physical-iPhone acceptance. Refresh Safari and inspect NPC silhouettes, clear gathering/shop/travel access, shadow contact, rotating-camera views and the small non-blocking River bird.

## Web delivery

Ran `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1` with the existing WSL/Linux Godot 4.7.2 exporter; exit 0. PCK 31,825,268 bytes; project.binary 9,944 bytes with ECFG header. Existing HTTPS listener remained PID 2964 on 0.0.0.0:8060. No server restart or save change. Safari refresh is ready.

## Files changed

The complete 49-file source/report list for this pass is `docs/npc/world_population_v1_files.txt`; it excludes earlier uncommitted changes. The existing shared shadow scene change was preserved without editing it. No original sprite sheets, SpriteFrames, visual profiles, collision-family resources, shadow-family resources or gameplay-provider scripts were changed by this pass.
