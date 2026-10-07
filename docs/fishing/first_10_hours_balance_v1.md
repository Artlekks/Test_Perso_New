# First-10-Hours Balance v1 — Cash Flow & Progression Pacing

## Decision

Keep runtime prices, authored fish trades, ownership progression and the existing 8000z / 15500z H12 ceilings unchanged. No production balance knob or simulated catch rate was tuned in this pass. The evidence identifies a concentrated late fishing income stream and insufficient recurring cash expenditure, but does not establish a defensible new Salmon price, mandatory sink or replacement ceiling. Several known simulator abstractions also point in opposite directions. Forcing 24/24 now would hide that uncertainty.

Implemented exact cash-flow and per-species value/provenance ledgers in the existing simulator, plus regression assertions. Fixed its explanatory text: prepared bait currently changes modeled discovery only, not the modeled catch mix or vendor value. Added explicit reporting of the cooking/Card Maker mismatches. All pre-pass checkpoint fields, purchases, timings and all 24 guardrail definitions/results remain identical; QA verifies this against the preserved baseline. These are reporting corrections, not a claim that the live-recipe/time-budget simulator reconciliation is finished.

The baseline is the repaired normal Beach -> Ocean -> Lake -> River -> Chiqua model from commit `28eccdd`. All money below is expected-value simulated Zenny, not measured human play. No save schema, live fishing mechanics, rod combat behavior, camera, merchant/world architecture, Triple Triad rules or shadow code changed.

## Exact wallet decomposition

Starting cash + fish sales + other income - progression purchases - Card Maker cash - other cash expenditure = ending wallet. The simulator has zero other income and zero other cash expenditure. Every progression cash purchase is already in the gear total; it must not be deducted twice. Fish trades and crafting materials are opportunity costs, not additional cash debits after those fish have already been excluded from sales. Values below are rounded to two decimals for reading; the JSON contains full precision and QA reconciles the unrounded figures.

| Profile | Hour | Start | Fish sales | Progression cash | Card Maker cash | Ending wallet |
|---|---|---:|---:|---:|---:|---:|
| Balanced | H1 | 100 | 1558.21 | 250 | 0 | 1408.21 |
| Balanced | H4 | 100 | 2920.58 | 250 | 328.39 | 2442.19 |
| Balanced | H10 | 100 | 10649.91 | 1950 | 1918.57 | 6881.34 |
| Balanced | H12 | 100 | 14867.48 | 1950 | 2480.17 | 10537.30 |
| Sell-heavy | H1 | 100 | 2457.17 | 250 | 0 | 2307.17 |
| Sell-heavy | H4 | 100 | 4605.53 | 250 | 82.10 | 4373.43 |
| Sell-heavy | H10 | 100 | 16794.09 | 1950 | 479.64 | 14464.45 |
| Sell-heavy | H12 | 100 | 23444.87 | 1950 | 620.04 | 20974.82 |

H12 equations: Balanced `100 + 14867.4772096181 - 1950 - 2480.17316938113 = 10537.304040237`; Sell-heavy `100 + 23444.8679074747 - 1950 - 620.043292345283 = 20974.8246151294`. Displayed integer wallets are 10537 and 20975.

H12 purchase spending is 4430.17z Balanced and 2570.04z Sell-heavy. Gear spending is the same 1950z: Baby Frog 250 + Floater 300 + Popper 350 + Silver Top 450 + Hanger 600. Gear spending ends at H9. The two profiles have identical modeled caught species, but Sell-heavy sells 82% of discretionary fish versus Balanced's 52%, and allocates fewer fish/cash to side systems. Its extra 8577.39z sale income plus 1860.13z lower Card Maker expenditure accounts for the entire 10437.52z wallet difference.

## Opportunity costs and retained wealth

Both profiles' 160 catches have 34216.30z potential catalog sale value. The per-species ledger allocates that potential value exactly:

| H12 allocation | Balanced value | Sell-heavy value |
|---|---:|---:|
| Sold, producing wallet income | 14867.48 | 23444.87 |
| Consumed in four progression fish trades | 5625.00 | 5625.00 |
| Retained in the fish bank | 6657.02 | 2950.86 |
| Allocated to the pooled prepared-bait model | 4002.78 | 1429.57 |
| Allocated to the pooled Card Maker model | 3064.02 | 766.01 |

Trade costs: Bamboo Sea Bream x2 = 700z; Tail Flying Fish x3 = 90z; Crab Black Bass/Blue Gill/Piranha x1 = 435z; Angling Salmon/Dorado/Martian Squid x2 = 4400z. Total 14 fish / 5625z. Trades actively suppress income; they do not create free sale money or double counting. Relative to selling the same released fish under each profile's behavior, reservation diverts 2925z Balanced and 4612.50z Sell-heavy of potential direct sales, before side-use/crafting interactions.

The retained bank and gear/cards are also player wealth, but the old guardrails measure liquid cash only. They should not be conflated with total net wealth. At H12 the pooled cooking model consumes 20.44 fish Balanced and 7.30 Sell-heavy; herbs consumed are 40.88 / 14.60 units. At the authored Coastal Herb 2z material value their opportunity cost is 81.76 / 29.20z, with no cash crafting fee. The model does not track realized Beach lure crafting or material sales, so those additional opportunities cannot honestly be assigned a numeric debit/income. Cooking allocations are not proof that these exact species are valid runtime ingredients.

## What drives excess cash

1. **Late Salmon income dominates.** Salmon generates 5442.27z Balanced and 8582.04z Sell-heavy: 36.61% of total H12 fish income. H10-H12 adds 26 successful catches, including 6.81475 expected Salmon. Salmon contributes 3543.67 / 5588.09z, or 84.02% of that interval's gross sale income. The remaining late species contribute Rainbow Trout 207.57 / 327.33z, Trout 309.32 / 487.77z, Browntail 105.95 / 167.07z, Jellyfish 51.05 / 80.51z. No new gear purchases offset these sales; Card Maker spends only 561.60 / 140.40z during that interval.
2. **The post-spine River 2 mix has a high value/frequency combination.** The normal neutral Straight lure / 50% depth mix makes Salmon about 26.21% of expected successful catches, despite its 15% base spawn weight, and averages 311.95z potential value per catch. The old SPECIALIZE abstraction used 180z per catch; the real neutral mix is 73.31% higher. Salmon is flagged for rendered landing-rate/fight-time measurement. Its 1000z price matches authored BOF4 source metadata; there is no proven accidental price override or duplicated reward here.
3. **Fixed successful throughput and free side activities are optimistic.** All profiles get the nominal successful catches/hour while travel, menus, gathering and card play consume no fishing time. There are no failed fights/casts, losses, consumable decisions or vendor trips. Species are sampled from bite weights as though all hooked species share the same landing success rate. This is not validated for tier-four Salmon. The model grants a continuous late fishing income stream, not a measured first-12-hour play session.
4. **Recurring cash sinks are weak for a sell-heavy player.** Only 1950z mandatory progression cash is authored into the normal spine. Fish trades, free material crafting and gathered cooking are valuable loops but cannot absorb liquid cash as fees. Sell-heavy intentionally minimizes optional card spending. Its stockpiled fish is smaller and its wallet is naturally larger.

Both profiles average 213.85z potential value per caught fish over H12. Actual cash earned per catch is 92.92z Balanced / 146.53z Sell-heavy; realized mean price per sold fish is 195.83z for both. Salmon + Black Bass + Bonito contribute 52.37% of total sale income. The complete species table below distinguishes unit sell price from cash actually earned per catch.

## Controlled contributor tests

These run only in an external in-memory analysis script, never in production resources or saves. They are causal/sensitivity probes, not proposed changes.

| Counterfactual | Balanced H12 | Sell-heavy H12 | Interpretation |
|---|---:|---:|---|
| Current model | 10537 | 20975 | Preserved baseline |
| Charge an extra 1000z for Bamboo while retaining its fish trade | 9537 | 19975 | Exact 1000z cash-only contribution; cannot explain all excess |
| Hypothetical Bamboo 1000z **instead of** fish, allowing its Sea Bream to enter discretionary use | 9894 | 20547 | Current fish-trade design increases net cash by about 643z / 428z versus this isolated hypothetical; the released fish offset much of the old cash price |
| Use only starter Straight lure at the same targeting depths and legal locations | 10535 | 20979 | Owned lure choice changes final wallet only -2z / +4z here; equipment is not a vendor-price multiplier |
| Unmeasured post-H9 fishing activity reduced to 75% | 9166 | 18533 | Illustrates sensitivity to unmeasured activity/time allocation |
| Unmeasured post-H9 fishing activity reduced to 50% | 7795 | 16092 | Preserves acquisition timings and H1/H4, but is not measured evidence for applying this rate |

Rod upgrades do not multiply sale prices or modeled throughput: direct income multiplier is zero. They unlock locations/gear and matter in live fight accessibility. Lure ownership affects the modeled targeting mix; the controlled Straight-only scenario does not prove lures lack live value. Prepared bait contributes zero modeled sale-price, encounter-frequency or quality uplift; its modeled effect is only discovery. Live attraction can improve bite timing and quality can improve points/size, but the vendor price is fixed by species. Those effects require a cast/fight-time model before assigning a cash increment.

The hypothetical old cash purchase is isolated at the existing Bamboo acquisition step for attribution; it is not a new playable source or reinstated Faerie access. All prices/recipes remain unchanged in the project. The sensitivity script's first draft used a nonexistent spot lookup and was discarded after script errors; the corrected `balance-sensitivity-final.log` run exits cleanly and is the sole source for this table.

## Intended sinks inspected

| System | Existing live cost | What the current simulation does / what is missing |
|---|---|---|
| Prepared bait | One eligible common fish + two Coastal Herbs -> three portions; no cash fee | Uses fractional fish of any species; consumes portions per successful catch instead of per cast. No failed-cast/quality/attraction throughput model. This overstates some high-value fish expenditure and understates failed-cast portion use. |
| Beach crafting | Authored material combinations, no Zenny crafting fee | No realized crafting/material ledger. Three-part material opportunity cost depends on the actual combination; do not invent a fee. |
| Card Maker | Five authored species recipes; first print 1 fish + 75z, duplicates 0 fish + 150z; availability depends on owned card/backend and visiting Beach | Generic pooled fish and 100/180z fees; fractional prints/uniqueness and automatic access away from Beach. The model cannot determine first/duplicate costs from a scalar unique-card count. Correcting the fees alone would leave invalid recipes/access and generally increase cash. |
| Progression purchases | Baby Frog 250, Floater 300, Popper 350, Silver Top 450, Hanger 600 | Included exactly; no missing required cash item. |
| Replacement/alternate gear | Extra purchases where a normal provider exposes them; optional Straight 200 / Wooden Rod 500, plus existing shop alternatives | No observed loss/replacement cadence. No durability/repair fee exists to activate. Other catalog rods do not become normal-route offers merely because the debug catalog contains them. |
| Fishing consumables | Optional consumption of existing fish for session effects | No observed use cadence. These consume inventory/opportunity value, not an invented mandatory Zenny sink. |
| Triple Triad | Card stakes/recovery; optional cash Card Maker, no arbitrary recurring duel fee | Card activity rates are abstract. Do not change rules or force duplicate purchases for a minimally card-engaged profile. |

There is no omitted mandatory recurring cash sink that can be enabled safely to remove the remaining 2537.30z / 5474.82z. Meeting those gaps solely with extra 150z duplicate cards would require 17 extra prints Balanced and 37 Sell-heavy, contradicting the latter's intended behavior. Raising early gear prices, adding taxes, or forcing replacement spending would be new design, not activating authored costs.

## Ceilings: assessment and decision

The model demonstrates generosity relative to the targets, especially the Salmon-dominated late loop. It does **not** establish that the actual runtime is too generous at human landing rates, nor that the old ceilings are obsolete. Intended progression changes account for some cash difference, while the old 180z average and unmeasured full-time throughput fail to describe the current loop. Both intended wealth and model bias contribute; choosing conclusively between runtime A/B/C still needs rendered rates and a recipe-valid side-system model. Keep both targets as stress warnings rather than declaring them obsolete or forcing green.

No replacement target is proposed or applied. The original 8000z / 15500z distinction remains intact. At fixed catches/allocations, meeting Balanced solely with a Salmon price change requires at most 533.78z; meeting Sell-heavy requires at most 362.06z. A roughly 64% price cut just to satisfy the latter is not justified by the evidence. Half-time post-H9 fishing nearly meets both without any price change, demonstrating how strongly the answer depends on a presently unmeasured assumption. These alternatives are not applied.

## Acquisition pacing

Both profiles have the same deterministic timing:

| Item | Design checkpoint | Acquired | Source / requirement |
|---|---:|---:|---|
| Baby Frog | H0.75 | H0.75 | Beach, 250z |
| Bamboo Rod | H2.25 | H2.25 | Ocean Manillo, Sea Bream x2 |
| Tail | H3 | H3 | Ocean Manillo, Flying Fish x3 |
| Crab | H3.5 | H3.5 | Lyp Manillo, Black Bass/Blue Gill/Piranha x1 |
| Floater | H5 | H5 | Beach, 300z |
| Popper | H6 | H6 | Lyp shop, 350z |
| Angling Rod | H7 | H7.25 | Lyp Manillo, Salmon/Dorado/Martian Squid x2 |
| Silver Top | H8 | H8 | Lyp shop, 450z |
| Hanger | H9 | H9 | Chiqua, 600z |

No item is earlier than its modeled time floor. Only Angling misses its floor, by one 15-minute step. The floors are simulator design assumptions; the live game has ownership/fish gates and can be faster/slower. These times do not prove natural runtime pacing. Bamboo needs about 11.24 successful catches for Sea Bream x2 under early Baby Frog/deep targeting; Tail needs about 9.37 for Flying Fish x3, with overlapping bank accumulation. A fixed pre-Crab Baby Frog/mid-depth mix needs about 8.06 successful catches to obtain all three Crab species x1 (coupon-collection expectation). Hanger is cash-feasible and source-gated rather than grind-blocked in both profiles.

Martian Squid targeting with the pre-Angling owned Crab lure, neutral environment, reeling and 50% depth has probability 0.1272564053 per normalized expected successful catch. Two Squid therefore need **15.7163 successful catches on average**, about 1.21 modeled fishing hours at 13/hour if none are already banked. Independent fixed-mix completion probability is `1-(1-p)^n-n*p*(1-p)^(n-1)`: 35 catches gives 94.79%; **36 catches gives 95.35%**, about 2.77 modeled fishing hours. This excludes real bite wait, failed fights, navigation and player targeting variation; prior banked Squid reduces remaining effort. Dorado x2 averages 8.16 and Salmon x2 11.59 under their separate pre-Angling targeted mixes, so they cannot simply be added as mutually exclusive catches; incidental required fish accrue together. Squid's long tail remains the clearest acquisition play-feel risk, but no recipe or spawn weight was altered.

## QA, commands and files

Godot: `C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe` (4.7.2.stable.official.ed1daf0bf). All gameplay fixtures use disposable custom userdata; the normal save is untouched. Artifact root `A` is `C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c`.

Each regression command uses `--headless --path . --quit-after 1800 --log-file A/<log> --script <script>`, plus the user arguments below. The existing isolation wrappers configure userdata before calling the original suites. Campaign and fresh-save suites actually run through session initialization and full world integration; they are not separate graphical rehearsals.

| Script / arguments | Log | Actual result |
|---|---|---|
| `res://scripts/qa/runtime_economy_reconciliation_qa.gd -- --baseline=A/economy-balance-v1-before.json --report=A/economy-balance-v1-after.json` | `balance-reconciliation.log` | 1029/1029 invariants, including all original 177; exit 0. New exact cash/species conservation, canonical prices, no invented income/sinks, every original checkpoint field and unchanged 24 guardrails. |
| `res://scripts/qa/world_location_access_qa.gd` | `balance-final-world.log` | Architecture 566/566; complete suite 571/573, exit 1, same aggregate campaign/fresh-save failures. All nine acquisitions and normal routes pass. |
| `A/world_economy_access_qa_isolated.gd` | `balance-final-economy.log` | 80/81, exit 1 solely aggregate simulator-health assertion. Foundation 13/13; economy/trade/full-access groups 208/208. |
| `A/early_tackle_acquisition_qa_isolated.gd` | `balance-final-acquisition.log` | 60/61, exit 1 solely aggregate campaign health. Director 14/14, Guide 8/8, Campaign Presentation 9/9. |
| `res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions` | `balance-final-fishing.log` | Fight camera 120/120; full fishing 22950/22950; exit 0. Fight 24/24, Presentation 10/10, Stability 27/27. |
| `A/balance_sensitivity.gd` with `--quit-after 600` | `balance-sensitivity-final.log` | Clean analysis run, exit 0; candidate rates/fees never applied to project. |
| `git diff --check` | Console | Exit 0. |

Campaign Loop remains 13/14 and Fresh Save Rehearsal 54/55 solely through the unchanged economy-health dependency. All 24 economy guardrails ran: **22/24**, unchanged. Balanced 10537 > 8000 and Sell-heavy 20975 > 15500 remain visible failures. Existing expected Triple Triad precomposition warnings occur; no script errors occur in final regression logs. Headless QA proves data/accounting/integration, not visual play-feel or real rates.

Changed project files: `scripts/progression/economy_progression_simulator.gd` (report-only allocation provenance, cash/species ledgers and accurate assumption descriptions), `scripts/qa/runtime_economy_reconciliation_qa.gd` (ledger and baseline regression checks), `docs/fishing/first_10_hours_balance_v1.md` (this report). No authored runtime economy data was edited.

Preserved baseline JSON: `A/economy-balance-v1-before.json`; ledger report: `A/economy-balance-v1-after.json`; controlled cases: `A/balance-sensitivity.json`; complete per-species exports: `A/balance-BALANCED-species.csv` and `A/balance-SELL_HEAVY-species.csv`. Reproduction/probe scripts remain outside the project.

Human validation still needed: measure successful landed catches and bite/fight minutes by species in normal River 2; include travel/vendor/menu/card/gathering time in a fresh-save session; record failed casts/fights, bait per cast, actual first/duplicate Card Maker choices and replacement/consumable use; test Squid two-copy tail effort. Those measurements should determine the next simulator behavior correction or modest Salmon/availability tuning. Neither the runtime generosity verdict nor a revised H12 ceiling is finalized by this pass.

## Baseline -> after checkpoints

All values in the following table are both baseline and after; **every difference is zero**, including all existing detailed ledgers and acquisition events. Cash is the existing integer display; the full-precision audit is above. Purchase spending includes gear and Card Maker, and retained fish counts include general kept fish plus any pending progression reservation.

| Profile | Hour | Zenny before -> after | Catches | Species | Cards | Rods | Lures | Bait remaining | Acquired | Retained fish | Traded fish | Purchase spending | Fish-sale income |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| BALANCED | H1 | 1408 -> 1408 | 20 | 5 | 7 | 1 | 2 | 3 | 1 | 8.44 | 0 | 250.00 | 1558.21 |
| BALANCED | H4 | 2442 -> 2442 | 56 | 12 | 15 | 2 | 4 | 1 | 4 | 14.10 | 8 | 578.39 | 2920.58 |
| BALANCED | H10 | 6881 -> 6881 | 134 | 21 | 27 | 3 | 8 | 1 | 9 | 28.68 | 14 | 3868.57 | 10649.91 |
| BALANCED | H12 | 10537 -> 10537 | 160 | 21 | 31 | 3 | 8 | 1 | 9 | 34.40 | 14 | 4430.17 | 14867.48 |
| SELL_HEAVY | H1 | 2307 -> 2307 | 20 | 5 | 6 | 1 | 2 | 2 | 1 | 4.77 | 0 | 250.00 | 2457.17 |
| SELL_HEAVY | H4 | 4373 -> 4373 | 56 | 11 | 11 | 2 | 4 | 0 | 4 | 6.83 | 8 | 332.10 | 4605.53 |
| SELL_HEAVY | H10 | 14464 -> 14464 | 134 | 19 | 17 | 3 | 8 | 0 | 9 | 12.57 | 14 | 2429.64 | 16794.09 |
| SELL_HEAVY | H12 | 20975 -> 20975 | 160 | 21 | 19 | 3 | 8 | 0 | 9 | 15.17 | 14 | 2570.04 | 23444.87 |

## Complete H12 species concentration

Fractional catches are expected values, not fractional live inventory. Unit price is canonical vendor value. Cash/catch includes fish consumed, allocated or retained rather than sold. Both profiles have identical catches; sale shares and income differ.

| Species | Caught, each profile | Unit price | Balanced sold | Balanced income | Balanced cash/catch | Sell-heavy sold | Sell-heavy income | Sell-heavy cash/catch |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| salmon | 12.4659 | 1000 | 5.4423 | 5442.27 | 436.57 | 8.5820 | 8582.04 | 688.44 |
| black_bass | 10.5852 | 250 | 4.9843 | 1246.07 | 117.72 | 7.8598 | 1964.96 | 185.63 |
| bonito | 3.0174 | 700 | 1.5690 | 1098.32 | 364.00 | 2.4742 | 1731.97 | 574.00 |
| octopus | 4.3203 | 400 | 2.2466 | 898.63 | 208.00 | 3.5427 | 1417.07 | 328.00 |
| rainbow_trout | 4.6093 | 320 | 2.3969 | 766.99 | 166.40 | 3.7797 | 1209.49 | 262.40 |
| martian_squid | 5.5101 | 400 | 1.8253 | 730.10 | 132.50 | 2.8783 | 1151.31 | 208.95 |
| dorado | 3.5679 | 800 | 0.8153 | 652.26 | 182.81 | 1.2857 | 1028.56 | 288.28 |
| blue_gill | 8.8369 | 150 | 4.0752 | 611.28 | 69.17 | 6.4263 | 963.94 | 109.08 |
| sea_bream | 5.1584 | 350 | 1.6424 | 574.84 | 111.44 | 2.5899 | 906.47 | 175.73 |
| trout | 21.7625 | 50 | 11.3165 | 565.83 | 26.00 | 17.8453 | 892.26 | 41.00 |
| browntail | 4.1826 | 180 | 2.1749 | 391.49 | 93.60 | 3.4297 | 617.34 | 147.60 |
| bass | 10.2272 | 70 | 5.3182 | 372.27 | 36.40 | 8.3863 | 587.04 | 57.40 |
| spearfish | 0.3215 | 1500 | 0.1672 | 250.73 | 780.00 | 0.2636 | 395.39 | 1230.00 |
| sea_bass | 11.8295 | 40 | 6.1513 | 246.05 | 20.80 | 9.7002 | 388.01 | 32.80 |
| blowfish | 5.0160 | 80 | 2.6083 | 208.67 | 41.60 | 4.1131 | 329.05 | 65.60 |
| piranha | 12.2727 | 35 | 5.8618 | 205.16 | 16.72 | 9.2436 | 323.53 | 26.36 |
| man_o_war | 17.0800 | 20 | 8.8816 | 177.63 | 10.40 | 14.0056 | 280.11 | 16.40 |
| flatfish | 0.8702 | 300 | 0.4525 | 135.76 | 156.00 | 0.7136 | 214.08 | 246.00 |
| whale | 0.0977 | 2000 | 0.0508 | 101.63 | 1040.00 | 0.0801 | 160.26 | 1640.00 |
| flying_fish | 9.2889 | 30 | 3.2702 | 98.11 | 10.56 | 5.1569 | 154.71 | 16.66 |
| jellyfish | 8.9797 | 20 | 4.6694 | 93.39 | 10.40 | 7.3633 | 147.27 | 16.40 |

## H10 -> H12 incremental species

| Species | Additional catches, each | Balanced sales income | Sell-heavy sales income |
|---|---:|---:|---:|
| salmon | 6.81475 | 3543.67 | 5588.09 |
| rainbow_trout | 1.24745 | 207.57 | 327.33 |
| trout | 11.89693 | 309.32 | 487.77 |
| browntail | 1.13194 | 105.95 | 167.07 |
| jellyfish | 4.90893 | 51.05 | 80.51 |

All other species have zero incremental catches/sales in this interval. Full H1/H4/H10/H12 per-species rows are retained in the JSON ledger report.
