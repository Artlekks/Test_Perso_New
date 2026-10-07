Runtime Economy & Pacing Reconciliation v1 — 7 October 2026

The simulator has been reconciled, but the current nine-step runtime route is **blocked**, and the project is **not fully green**. This pass does not repair world authoring or rebalance anything. Baseline commit: `7c1832f`. Baseline simulator: 24/24 existing guardrails; Bamboo-only migration: 22/24; full runtime reconciliation: 19/24. Guardrail thresholds are unchanged.

**What the playable data actually says**

Fresh inventory starts with Wooden Rod, Straight, 100z and no cards. The intended ownership ladder comes from `data/progression/early_tackle_acquisition_v1.json`. These prices come from the same `FishingEconomyConfig.get_offer_buy_price` resolution used by `FishingEconomyService.evaluate_purchase`, with the authored offer price as fallback.

| Order | Target | Authored source | Cash or exact fish cost | Location / required access | Required fishing / inventory state |
|---|---|---|---|---|---|
| 1 | Baby Frog | `shyde_baby_frog` | 250z | Beach Merchant, Beach / Ocean 2; initially available | Wooden Rod + Straight; earn at least 150z beyond the starting wallet |
| 2 | Bamboo Rod | `wyndia_bamboo_rod` | Sea Bream x2 | Wyndia Manillo, Ocean 1; Baby Frog ownership opens Ocean | Wooden Rod, Straight/Baby Frog; reserve two Sea Bream from Ocean 1 |
| 3 | Tail | `wyndia_tail` | Flying Fish x3 | Same Ocean 1 trader | Intended ladder already owns Bamboo; reserve three Flying Fish from Ocean 1. The recipe itself does not require the rod |
| 4 | Crab | `lyp_crab` | Black Bass x1, Blue Gill x1, Piranha x1 | Lyp Manillo / Lake 2; hint says Bamboo + Tail, but serialized gates and provider paths are missing | Intended pre-Crab equipment: Bamboo, Baby Frog, Tail. All three fish have positive Lake 2 bite weights; **trade access currently broken** |
| 5 | Floater | `shyde_floater` | 300z | Beach Merchant; intended return from Lake through Ocean | Ladder owns Crab; recipe/offer has no Crab gate. **Lake currently has no return route** |
| 6 | Popper | `lyp_popper` | 350z | Lyp Item Shop / Lake 2 | Ladder owns Floater. **Lyp item-shop binding currently broken** |
| 7 | Angling Rod | `lyp_angling_rod` | Salmon x2, Dorado x2, Martian Squid x2 | Lyp Manillo; Salmon at River 2, Dorado/Squid at Lake 2 | Bamboo + pre-Angling lures. River requires Crab + Floater + Popper; **Lake has no River route and no usable trade binding** |
| 8 | Silver Top | `lyp_silver_top` | 450z | Lyp Item Shop | Intended ladder already owns Angling Rod; **binding broken** |
| 9 | Hanger | `chiqua_hanger` | 600z | Chiqua Item Shop, accessed from River; requires Angling Rod + Silver Top | All preceding gear; **Chiqua is unreachable through the current Lake graph** |

Travel dependencies are ownership-based, not simulator-hour gates. Intended chain: Beach → Baby Frog → Ocean → Bamboo/Tail → Lake → Crab/Floater/Popper → River → Salmon plus Lake Dorado/Squid → Angling/Silver Top → Chiqua/Hanger. The runtime currently has no Lake outbound destinations, no Lake equipment requirements, and zero provider paths for its two contexts. `WorldLocationService.context_belongs_here` consequently rejects those contextual providers. The scene still contains `World/ManilloTrader`, `World/LypItemShop`, `ReturnTravel` and `RiverTravel`; their existence alone does not restore the missing metadata.

The source recipes do not enforce this entire sequential ladder individually. The simulator follows the authored acquisition order intentionally. Floater can otherwise be bought on Beach whenever affordable; this is legitimate runtime flexibility, not a new hard unlock.

Balanced deterministic acquisition events actually achieved: Baby Frog H0.75, cash 1605.13→1355.13z; Bamboo H2.25, cash 1808.22→1808.22z and Sea Bream x2 consumed; Tail H3, cash 2132.10→2132.10z and Flying Fish x3 consumed. Later inventory/cash-at-acquisition cannot be reported because those acquisitions are blocked. Later checkpoint wallets are stalled-route projections, not successful nine-step playthrough results.

**Mismatches and decisions**

| Old assumption | Runtime evidence | Classification / action |
|---|---|---|
| Baby Frog from `sarai_baby_frog` | Ownership guidance uses `shyde_baby_frog`, Beach | Outdated simulator source; derive from the ownership plan |
| First Bamboo from `faerie_bamboo_rod`, 1000z | Guidance uses `wyndia_bamboo_rod`, Sea Bream x2 | Outdated intended source; migrate the simulator. The 1000z Faerie alternate remains authored and valid; no shop/recipe was removed |
| Fish requirements repeated in simulator dictionaries | Trade recipes already expose `get_cost_dictionary()` | Fragile duplication; derive requirements from those recipes |
| Fixed stage catch mixes, including Flying Fish/Piranha/Blue Gill/Sea Bream in LEARN | Fresh Beach is Ocean 2: Sea Bass, Flatfish, Bonito, Man-o'-War, Octopus, Spearfish, Whale | Outdated population assumptions; derive normalized runtime bite weights from reachable spots and owned lures |
| Every authored catalog source is accessible | Contextual source access requires ownership, directed routes and correctly bound scene providers | Outdated access assumptions; validate route, provider node and exact context binding; track current simulated location |
| Stage average sale values 45/90/180z plus up to 30% bait uplift | Runtime vendor values are fixed per species; size/quality does not multiply its sale price | Outdated income assumptions; price each unreserved sold species canonically, without a fictitious vendor uplift |
| Lake is gated and connects Ocean/River with two providers | Serialized Lake resource omits all three sets of metadata | Unintended runtime contradiction; expose it, do not silently repair it |
| Rod display says Faerie 250z | Canonical economy resolves the alternate to 1000z | Stale display/reference text; not modified in this pass |
| Scheduled acquisition hours | Runtime progression uses ownership | Acceptable design goals only; hours never bypass access/cash/fish requirements |
| Fractional catches, fixed success throughput, herb/card/discovery rates and prepared-bait loop | Live play is stochastic and uses spatial fish, environment, hook/fight skill and actual system transactions | Explicit retained design abstractions; no claim of rendered pacing validation |

The adapter reads the runtime ownership plan, trade/offer catalogs, canonical economy config, world-location service, real population entries and their `get_bite_selection_weight` method. Provider scenes are instantiated only as detached inspection fixtures, checked once per adapter, then freed. Nothing changes live scenes, save data or runtime resources. Empty/unknown route origins expose no population or fake destination. Zero-time travel is modeled only through reachable directed routes; after entering broken Lake the simulated player cannot silently return to Beach.

**Exact reservation policy**

Outstanding authored progression requirements are reserved before selling, bait cooking, card-making or discretionary keeping. The species catch batch is reduced by those reservations; only the remainder earns sale income. Trade consumption updates a separate species ledger and reduces the bank. General kept fish remain separate from the capped progression-reservation display. QA checks total conservation across sales, remaining reserves, trade costs, bait ingredients/banks and card ingredients/banks.

| Trade | Species held / consumed | Total fish | Foregone full-sale value |
|---|---|---|---|
| Bamboo | Sea Bream x2 | 2 | 700z |
| Tail | Flying Fish x3 | 3 | 90z |
| Crab | Black Bass x1 + Blue Gill x1 + Piranha x1 | 3 | 435z |
| Angling | Salmon x2 + Dorado x2 + Martian Squid x2 | 6 | 4400z |
| Entire intended spine | All above | 14 | 5625z |

Purchased progression gear totals 1950z: Baby Frog 250, Floater 300, Popper 350, Silver Top 450, Hanger 600. These values and trade quantities were not changed. The foregone-sale figures assume every fish would otherwise be sold; Balanced/Sell-heavy allocate some to other systems, so the simulator's actual opportunity cost differs.

**Bamboo-only migration, holding all other historical assumptions fixed**

This controlled comparison uses the original simulator snapshot with only Bamboo's authored source changed; it deliberately retains the old hypothetical populations/access and is not presented as runtime pacing. All historical purchase timing stays H2.25 for Bamboo; every other intended checkpoint acquisition remains the same. At H1, the extra two Sea Bream have already been reserved; at H4 they are consumed. Total intended progression fish spent rises from 12 to 14 by H10/H12.

| Profile | Checkpoint | Wallet before → migration-only | Fish sold before → migration-only | Progression fish spent before → migration-only |
|---|---|---|---|---|
| Balanced | H1 | 201 → 154 | 8 → 7 | 0 → 0 |
| Balanced | H4 | 612 → 1555 | 25 → 24 | 6 → 8 |
| Balanced | H10 | 5070 → 6013 | 63 → 62 | 12 → 14 |
| Balanced | H12 | 7248 → 8191 | 77 → 76 | 12 → 14 |
| Sell-heavy | H1 | 403 → 330 | 12 → 11 | 0 → 0 |
| Sell-heavy | H4 | 1878 → 2799 | 39 → 38 | 6 → 8 |
| Sell-heavy | H10 | 11168 → 12089 | 100 → 98 | 12 → 14 |
| Sell-heavy | H12 | 15038 → 15959 | 121 → 120 | 12 → 14 |

Migration alone fails two unchanged cash guardrails: Balanced H12 8191 > 8000; Sell-heavy H12 15959 > 15500. It produces net H12 gains of 943z and 921z, rather than the full avoided 1000z, because reserving fish reduces sales and affects subsequent resource allocation.

**Historical baseline → fully reconciled current-data results**

Each arrow is before → after. Catch throughput is intentionally unchanged: H1 20, H4 56, H10 134, H12 160 for both profiles. Display values are rounded expected counts; accounting QA operates on unrounded values. Rod/lure counts include the starter equipment. Bait means remaining prepared-bait portions, not batches.

| Profile | Hour | Zenny | Species | Cards | Rods | Lures | Prepared bait | Fish sold |
|---|---|---|---|---|---|---|---|---|
| Balanced | H1 | 201 → 1408 | 5 → 5 | 7 → 7 | 1 → 1 | 2 → 2 | 3 → 3 | 8 → 9 |
| Balanced | H4 | 612 → 2442 | 12 → 12 | 15 → 15 | 2 → 2 | 4 → 3 | 1 → 1 | 25 → 24 |
| Balanced | H10 | 5070 → 8018 | 21 → 16 | 27 → 27 | 3 → 2 | 8 → 3 | 1 → 1 | 63 → 63 |
| Balanced | H12 | 7248 → 10113 | 23 → 16 | 32 → 31 | 3 → 2 | 8 → 3 | 1 → 1 | 77 → 77 |
| Sell-heavy | H1 | 403 → 2307 | 5 → 5 | 6 → 6 | 1 → 1 | 2 → 2 | 2 → 2 | 12 → 14 |
| Sell-heavy | H4 | 1878 → 4373 | 11 → 11 | 11 → 11 | 2 → 2 | 4 → 3 | 0 → 0 | 39 → 38 |
| Sell-heavy | H10 | 11168 → 15334 | 19 → 16 | 17 → 17 | 3 → 2 | 8 → 3 | 0 → 0 | 100 → 100 |
| Sell-heavy | H12 | 15038 → 19383 | 22 → 16 | 19 → 19 | 3 → 2 | 8 → 3 | 0 → 0 | 121 → 121 |

Progression gear before: H1 Baby Frog; H4 Baby Frog/Bamboo/Tail/Crab; H10/H12 all nine. After: H1 Baby Frog; H4/H10/H12 Baby Frog/Bamboo/Tail only. The simulator refuses to treat catalog existence or wallet size as a substitute for Lyp world access.

Progression fish currently reserved, same targeted quantities for both profiles:

| Checkpoint | Before | After |
|---|---|---|
| H1 | Flying Fish x3, Blue Gill x1, Piranha x1; no Bamboo Sea Bream reservation | Sea Bream 0.8894/2, Flying Fish 1.6015/3; remaining targets zero |
| H4 | Future Angling bank includes Martian Squid x2; Salmon/Dorado zero | Black Bass/Blue Gill/Piranha x1 each; Dorado 0.7276/2; Martian Squid 0.8920/2; Salmon zero |
| H10/H12 | All progression trade reservations consumed; general kept fish remain | Crab's three fish still held; Dorado x2, Martian Squid x2 held; Salmon zero because River is unreachable |

The after model spends five progression fish (Bamboo two + Tail three). Crab's bank is complete, so the blocker is provider access, not repeated catch requirements. Additional general keeps can raise a species bank above its outstanding trade requirement; the progression-reservation display caps it to the actual outstanding need.

**Guardrails and pacing risks**

The fully reconciled model passes 19/24 original guardrails. Failed checks:

| Existing guardrail | Actual | Required | Cause |
|---|---|---|---|
| Balanced H4 Crab | Not acquired | Acquired | Missing Lyp provider metadata |
| Balanced H12 Angling Rod | Not acquired | Acquired | Missing Lyp provider / Lake-to-River route |
| Balanced H4 useful lures | 3 | At least 4 | Crab cannot be traded |
| Sell-heavy H12 cash | 19383z | At most 15500z | Canonical sale values plus stalled progression spending; success-throughput assumption is optimistic |
| Balanced H12 cash | 10113z | At most 8000z | Same issue, plus removal of first Bamboo cash sink |

The other 19 original checks pass, including first lure, first rod, H1 cards/species, H4/H12 collection bands, crafter cash buffer, prepared-bait use and Card-heavy progression. Full per-check results are in the captured JSON report.

Base bite probabilities at the actual source populations: Ocean Sea Bream 17%, Flying Fish 30%; Lake Black Bass 18%, Blue Gill 18%, Piranha 20%, Dorado 12%, Martian Squid 12%; River Salmon 15%. These are not catch-success probabilities.

Neutral targeted bite-weight estimates with **pre-target owned equipment**, reeling and target midpoint depth: Sea Bream 17.79% and Flying Fish 32.03% with Baby Frog at 82.5% depth; Black Bass 22.79%, Blue Gill 20.21%, Piranha 26.42% with Baby Frog at 50%; Martian Squid 12.73% with Crab at 50%; Dorado 24.52% with Popper at 17.5%; Salmon 17.26% with Popper at 17.5%. The latter are local fishing feasibility estimates conditional on restoring route access, not proof River is currently reachable.

Sea Bream x2 averages about 11.2 successful catches from a fixed targeted mix; Flying Fish x3 about 9.4, with substantial overlap when banking both simultaneously. Martian Squid x2 is the slowest intended fish reservation at about 15.7 successful catches, Salmon x2 about 11.6 and Dorado x2 about 8.2. An independent stationary 12.73% two-Squid model needs roughly 36 successful catches for 95% completion, about 2.8 hours at the assumed 13 successes/hour before real failures/travel. This is a suspected late-spine tail-risk bottleneck, not grounds for an automatic rebalance.

There is no demonstrated cash deadlock before Baby Frog: starter equipment and sellable Beach fish are available. Both tested profiles afford it at the retained H0.75 goal. Exact trade reservations total only 14 of the model's 160 successful catches at H12, but their 5625z full-sale opportunity cost and unlucky species repeats are material. Sell-heavy still reserves progression fish before selling and cannot bypass the world gates. Floater/Popper spending totals 650z and is not the observed blocker; bought-lure loss/replacement costs are excluded and need manual assessment. Richness estimates are especially sensitive to treating every selected rare/difficult Beach fish as a successful catch. No finding justifies changing prices now.

**Salmon with Bamboo**

Assessment: mechanically possible; provisionally a reasonably challenging advanced fight with a meaningful handling disadvantage, not an easy catch. Actual human difficulty, especially large/king specimens, remains unverified. The authoritative tier recommendation is a warning/QA label, not a hook gate.

Bamboo tier 1 versus recommended tier 2; reel speed 0.96, manual pull response 0.88, steering strength 0.84, steering response 0.78, counter-steer 0.85, twitch strength 0.90, rod hook security 0.90. Line tolerance and rod fatigue are 1.0. An average Salmon has stamina 103.5, strength 0.76, three resistance rounds, pressure/pull 1.14, recovery multiplier 1.10. Its profile has rapid 0.55–1.2s direction changes, 28% thrash chance and a 1.4 thrash multiplier.

Actual Beach Encounter scene overrides stamina drain to 60/s and tension safe band to 0.32–0.72, with 2.5s overload grace. Bamboo + Popper fatigue is 1.08 and combined hook-security multiplier 0.81, producing 0.648s slack escape grace. Average active-reel budget estimate is 4.79s over three rounds under ideal pressure, versus the existing 20s tier-four QA envelope; recovery, steering, reeling distance, structure and final surges add real difficulty.

The seeded headless scenario (`seed(71023)`) calls real `Encounter.try_hook()` with a River Salmon entry, Bamboo and Popper. It creates a non-king size ratio 1.1333 fish, stamina 117.3, strength 0.8107; the resolved context is valid and hooked. Calling production Encounter updates at 60Hz under ideal SAFE tension exhausts all three rounds to SPENT in 6.65s. Average-specimen fairness checks pass bite window, endurance, line and slack-grace envelopes. This does not simulate human tension control, a full physical retrieve, landing, catch persistence or a win rate. No fish/rod/recipe/fight value was changed.

**QA actually run**

Godot executable: `C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe`, version 4.7.2. All integration runs used disposable custom user-data directories; the normal player save was untouched.

| Suite | Result |
|---|---|
| New runtime economy reconciliation | 102/102 invariant checks; separate nine-step runtime viability FAIL |
| Original simulator guardrails | 19/24; five unmet, listed above |
| Economy foundation | 13/13 |
| Economy/trade/full-access regression groups | 208/208 |
| World Economy Access | 80/81; failing aggregate simulator-health assertion |
| Early Tackle Acquisition | 60/61; failing aggregate campaign-loop assertion |
| Campaign Loop | 12/14; milestone envelope and simulator-health assertions fail |
| Campaign Director / Guide / Presentation | 14/14, 8/8, 9/9 |
| Fresh Save Rehearsal | 54/55; campaign-loop-green dependency fails |
| Full fishing regression | 22950/22950 |
| Fight camera / Fight / Presentation / Stability | 120/120, 24/24, 10/10, 27/27 |
| World Location Access | FAILED / incomplete: missing Lake gate, mappings and River route; the live-scene harness later hits null `current_scene` and never emits its final count. Bounded runs at 1800 and 10000 frames ended; exit 0 from the frame limit is not a pass |
| `git diff --check` | Clean |

Commands used (each also supplied a unique `--log-file` in the artifact directory):

```powershell
& 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe' --headless --path . --quit-after 1800 --script res://scripts/qa/runtime_economy_reconciliation_qa.gd -- '--report=C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c/economy-after.json'
& 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe' --headless --path . --quit-after 1800 --script 'C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c/world_economy_access_qa_isolated.gd'
& 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe' --headless --path . --quit-after 1800 --script 'C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c/early_tackle_acquisition_qa_isolated.gd'
& 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe' --headless --path . --quit-after 10000 --script res://scripts/qa/world_location_access_qa.gd
& 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe' --headless --path . --quit-after 1800 --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions
git diff --check
```

The two external wrapper scripts only select isolated user storage then invoke the existing suite unchanged. The baseline and Bamboo-only diagnostic runners reconstruct the original simulator from commit `7c1832f`, add an H10 observation and capture JSON. They are evidence artifacts, not production scripts.

**Changed project files**

`scripts/progression/economy_progression_simulator.gd`, new `scripts/progression/economy_runtime_route.gd` and its generated `.uid`, new `scripts/qa/runtime_economy_reconciliation_qa.gd` and its generated `.uid`, and this report: six project files. Camera, shadows, save schema, prices, trade recipes, rod/fish stats, crafting, Triple Triad, merchants and travel authoring remain unchanged.

**Next balancing pass — recommendations only**

1. Repair and verify Lyp's provider paths, ownership gates and Ocean/River destinations in a separately authorized world-content fix. Rerun the complete nine-step route before treating H10/H12 completion as validated.
2. Recalculate both profiles once world access is correct; distinguish restored purchase sinks from the Bamboo migration's reduced cash sink.
3. Measure successful catches/hour, rare-fish catch failures, lure replacement, travel and menu time in rendered fresh-save play. Calibrate those simulator assumptions before altering prices or guardrails.
4. Test Bamboo + Popper/Crab against ordinary, large and king Salmon with real tension/steering. Check the Martian Squid two-catch tail and Ocean Sea Bream/Flying Fish shared grind.
5. Only then consider new spending sinks, encounter-rate tuning or pacing changes. No recommendation has been implemented here.

Incomplete: a successful live nine-step playthrough, completed location integration QA, rendered Salmon play-feel and real elapsed-hour validation. The content blocker and unchanged contract failures prevent a claim that this reconciliation is fully green.
