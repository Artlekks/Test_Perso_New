# Early Acquisition Spine v1 (0–4h)

Implemented a read-only runtime ownership ladder. The current beach only makes
the first step world-reachable. No new world location, trade NPC, fish population,
hour unlock, purchase price, recipe, save field, or reward was added.

## Reachability audit, completed before implementation

`project.godot` main-scene UID resolves to `actors/FishingTestScene_V2.tscn`.
The scene has one normal fishing zone, using `data/bof4/spots/ocean_2.tres`.
The Beach Merchant's existing `beach_merchant.tres` context grants only Shyde
shop access, with no Manillo trade IDs. No other placed merchant context grants
Wyndia, Lyp, or Faerie. Other spot resources are selectable through the debug
controller/menu; they are not normal map travel.

| Order | Target | Authored source | Cost | Normal world reachability |
|---|---|---|---|---|
| 1 | Baby Frog | shop offer `shyde_baby_frog` | live 250z | Beach Merchant; reachable |
| 2 | Bamboo Rod | Manillo recipe `wyndia_bamboo_rod` | Sea Bream ×2 | Wyndia Manillo world provider missing |
| 3 | Tail | Manillo recipe `wyndia_tail` | Flying Fish ×3 | Wyndia Manillo world provider missing |
| 4 | Crab | Manillo recipe `lyp_crab` | Black Bass ×1, Blue Gill ×1, Piranha ×1 | Lyp Manillo world provider missing |

Baby Frog's authored source reference price is separate from its canonical live
price. The QA executes normal contextual purchases and resolves 250z from the
existing economy service. Fresh cash is 100z. Ocean 2 has positive-weight Sea
Bass entries, and Sea Bass accepts the starter Straight lure. Four Sea Bass
sales at canonical 40z yield 260z, sufficient to buy Baby Frog and retain 10z.
QA supplies specimens in memory and exercises actual sale/purchase services;
it does not claim to have played four fishing fights manually.

## Fish content evidence

These IDs are derived from loaded authored populations with positive base bite
weight, not from journal location text. All five are absent from the current
Ocean 2 population, which instead contains Man-o'-War, Sea Bass, Flatfish,
Octopus, Bonito, Spearfish, and Whale.

| Required species | Authored eligible spots | Present in current normal zone |
|---|---|---|
| Sea Bream | `ocean_1`, `saldine` | No |
| Flying Fish | `ocean_1`, `ocean_3` | No |
| Black Bass | `lake_2`, `lake_3` | No |
| Blue Gill | `lake_1`, `lake_2` | No |
| Piranha | `lake_1`, `lake_2` | No |

Thus the Bamboo/Tail/Crab recipe requirements cannot currently be gathered by
normal early fishing. Their ingredients were preserved. Future maps must expose
the relevant fishing content before their intended trade stage. Authored spot
eligibility is not proof of a future map's travel, environment, gear, or difficulty
gates. The snapshot's `available_in_current_spots` is base bite eligibility in
currently registered zones; it does not model current weather or debug provenance.

## Bamboo decision and simulator effects

The selected long-term progression source is Wyndia's Sea Bream trade. It connects
fishing to equipment and gives fish a use beyond sale. Cash remains necessary for
Baby Frog, other purchases, crafting costs, and Card Maker fees.

The alternate `faerie_bamboo_rod` offer is preserved at canonical 1000z and requires
`faerie_diligent_shop` availability within `faerie_diligent` shop access. Faerie
has no playable merchant context. Either authored source can legitimately produce
ownership; guidance recognizes it without requiring the selected trade.

No simulator values or guardrails changed. Its historical design baseline still
buys Bamboo at 2.25h for 1000z and uses `sarai_baby_frog`; runtime guidance now
selects `wyndia_bamboo_rod` and `shyde_baby_frog`. The simulator is not a normal
world reachability certificate. Preserve that baseline until actual world trade
and fish-access content can justify a measured pacing comparison. Before/after
simulator wallets, acquisition timing, catch mix, and checks are identical (24/24).
The intended future trade costs zero direct zenny and consumes two Sea Bream,
whose present sell value is 350z each: 700z of foregone sale income versus the
1000z purchase. This is a cost comparison, not a measured simulation result.

## Runtime API and world wiring seam

`EarlyTackleAcquisition` reads one JSON plan, live inventory, the existing economy
service, and authored shop/trade/content catalogs. Prices and fish counts are not
copied into the plan. It exposes `targets`, `next_target`, and `complete`.
Each target reports source existence, current-world accessibility/reason,
ownership, wallet, resolved purchase price or exact fish owned/required/missing,
authored fish spot IDs, world provider paths, and concise guidance.

`PlayableCampaignProgressionDirector.get_tackle_acquisition_snapshot()` collects
existing contextual Resources from the `world_economy_sources` group and live
spots from `world_fishing_spots`. Both groups are filtered to the current scene
and exclude nodes queued for deletion. There are no cached actor references or
whole-scene scans. The regular campaign snapshot includes `tackle_acquisition`.
The Campaign Guide's LIVE row uses its existing tutorial text slot for the hint;
the main campaign objective and QA checkpoint tutorials are preserved.

For later world wiring, a real merchant/trader provider joins
`world_economy_sources` and exposes an `economy_context` Resource with its actual
shop/trade IDs and availability tags. Its transaction UI still must use the
existing contextual facade and provide the trade interaction. A fishing zone
joins `world_fishing_spots` and implements `get_fishing_spot()` (the existing
`fish_zone_v2.gd` does both). No Wyndia/Lyp IDs were attached to Beach Merchant.

Guidance never calls `set_access_context`, opens a menu, grants equipment, or
executes transactions. Debug full-catalog Resources do not count as normal world
access evidence. Progress advances from current ownership, regardless of source
or order, and contains no elapsed-time gates. Consumable equipment that is later
lost can become a target again; no historical completion field was added.

## Files changed

Modified:
- `scripts/beach_merchant_npc.gd`: register the existing contextual provider.
- `scripts/fish_zone_v2.gd`: register the existing fishing content provider.
- `scripts/fishing_session_services.gd`: configure the read-only acquisition composer.
- `scripts/progression/playable_campaign_progression_director.gd`: expose snapshots and current-scene provider collection.
- `scripts/progression/playable_campaign_qa_guide.gd`: show data-driven LIVE hint.

New:
- `data/progression/early_tackle_acquisition_v1.json`: source-linked ordered plan.
- `scripts/progression/early_tackle_acquisition.gd`: read-only acquisition API.
- `scripts/qa/early_tackle_acquisition_qa.gd`: isolated ownership/source/transaction/lifecycle QA.
- `docs/architecture/EARLY_TACKLE_ACQUISITION_V1.md`: this audit and implementation report.

## QA actually run

Godot 4.7.2 stable, headless. From the project directory, use:

```powershell
$godotExe = 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe'
$qaOutput = 'C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c'
& $godotExe --headless --path . --log-file "$qaOutput/early_tackle_qa.log" --script res://scripts/qa/early_tackle_acquisition_qa.gd | Out-String
& $godotExe --headless --path . --log-file "$qaOutput/early_world_economy_final.log" --script res://scripts/qa/world_economy_access_qa.gd | Out-String
& $godotExe --headless --path . --log-file "$qaOutput/early_world_interaction_final.log" --script res://scripts/qa/world_interaction_qa.gd | Out-String
& $godotExe --headless --path . --log-file "$qaOutput/early_tackle_runtime.log" --script "$qaOutput/early_tackle_runtime_qa.gd" | Out-String
git diff --check
```

The first runner uses a save-free memory inventory. Its 48 checks include all
ten requested categories, actual sell/buy transactions, alternate Faerie purchase
ownership, scene-provider exclusion, missing systems, and LIVE guide text.
It also runs existing Campaign Loop 14/14, Director 14/14, Guide 8/8, and
Presentation 9/9. These suites themselves were not edited.

World Economy Access: 45/45; Foundation 13/13; selected existing economy/trade/
full-access regression groups 208/208; First-10h simulator 24/24.
World Interaction: 93/93. Whitespace validation passed.

The external runtime QA runner loads the actual main scene with isolated
`user://` storage named `CodexEarlyTackleQA-20261007` (separate from FishingGame).
It verifies runtime Beach reachability, live price, and absence of the three
trade contexts. Fresh Save Rehearsal 55/55; System Stability 27/27; Item Backend
13/13; Card Maker 10/10; Mastery 64/64; Triple Triad Backend 101/101; Dialogue
175/175; Beach Crafting 14/14. Other existing fishing/master QA groups printed
successful results in `early_tackle_runtime.log`. This is not the entire general
fishing regression harness.

The initial runtime attempt lacked the newly selected user-data directory,
causing file-not-found warnings and Item Backend migration QA 12/13. After the
runner created its isolated directory, that suite passed 13/13. Early shutdown
also reported orphan/resource leaks; the final external harness frees orphan
Nodes left during the runtime QA run, and the final run reports no shutdown leaks.
The remaining Triple Triad warning comes from the backend's explicit
precomposition-rejection test, which passed. No gameplay cleanup behavior was
changed to silence these diagnostics.

## Coverage and remaining work

- [x] Four selected sources and both Bamboo alternatives inspected.
- [x] Canonical prices and authored recipes verified without changes.
- [x] Main scene, merchant contexts, fish populations, and debug spot switching traced.
- [x] Ownership, requirements, unavailable sources, debug isolation, and alternate source QA.
- [x] Existing economy/campaign/fresh-save QA executed in Godot.
- [ ] Normal Wyndia/Manillo map/provider plus trade UI and appropriate fish access.
- [ ] Normal Lyp/Manillo map/provider plus trade UI and freshwater fish access.
- [ ] Rendered Campaign Guide layout check at 640×480, especially the Crab hint.
- [ ] Manual fresh-game fishing → sell → Baby Frog purchase and LIVE guide refresh.
- [ ] Actual 0–4h playthrough/pacing validation after future world content is wired.

These unchecked items are incomplete world/presentation validation, not fictional
unlocks supplied by this pass. Fishing mechanics, cards, crafting, shadows,
contextual economy execution, save schemas, canonical prices, authored trade
ingredients, and simulator guardrails were preserved.
