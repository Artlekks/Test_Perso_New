# Content registration and provider binding validation v1

## Authority and boundaries

`WorldLocations` remains the runtime authority for location context, access and
travel. `data/world/location_registry.tres` is its single authored location list.
The route simulator reads that same resource; it does not maintain another list.

`data/world/provider_bindings_v1.json` is **validation metadata**, not an access
service. It cannot unlock travel, supply cards, teach techniques or offer items.
Scene exports and the existing runtime services retain their responsibilities.
The manifest gives each provider a unique ID, owning location, type, exact node
path, expected script and references. Catalogue-backed providers also identify
their shared catalogue. No gameplay base class was introduced.

| Domain | Authoritative registration |
| --- | --- |
| Locations, routes, equipment gates, economy providers | `data/world/location_registry.tres` → `data/world/locations/*.tres` |
| Live location context and provider access | `scripts/world/world_location_service.gd` |
| Fish and fishing spots | `data/bof4/catalogs/all_content.tres` |
| Populations | Each registered `FishingSpotData.fish_population`; fish references must resolve to the canonical fish resource |
| Lures and rods | `data/bof4/tackle/all_tackle.tres` and its lure catalogue |
| Shop offers | `data/bof4/shops/all_shops.tres` |
| Manillo recipes | `data/bof4/trades/all_trades.tres` |
| Contextual shop/trade exposure | Location `economy_contexts` paired with `economy_provider_paths`; context shop/recipe IDs are checked against those catalogues |
| Inventory item definitions | `GameItemCatalogService.configure()` derives namespaced definitions from materials, fish, tackle and economy configuration; it is an adapter, not a second authored ownership store |
| Crafting materials and recipes | `data/crafting/beach/beach_vertical_slice_catalog.tres` |
| Card Maker | `data/economy/card_maker/card_maker_catalog_v1.tres` |
| Card definitions | `data/triple_triad/card_catalog.tres` (authored atlas configuration with deterministic generated card IDs) |
| Opponents | `data/triple_triad/opponents/opponent_registry.tres` |
| Card acquisition bundles | `data/triple_triad/acquisition/acquisition_registry.tres` |
| Acquisition coverage and source contracts | `data/triple_triad/acquisition/world_acquisition_map.json` |
| Competitions | `data/triple_triad/competition/competition_catalog.json` |
| NPC visual assets | `data/npc/catalog/npc_catalog.tres` → entries/scenes/profiles |
| Mastery techniques and prerequisites | `data/bof4/mastery/all_techniques.tres` |
| Fishing rewards | `data/bof4/rewards/all_rewards.tres` |
| Early tackle acquisition plan | `data/progression/early_tackle_acquisition_v1.json`, resolved against real offers/trades and reachable location providers |
| World requests | `data/requests/request_catalog.tres`; scene request sources own runtime objective state |

NPC catalogue placeholder roles and suggested locations remain provisional
visual/content notes. They are never read as authoritative gameplay bindings.

## Audit findings and changes

1. The five playable locations were registered in a hardcoded preload array in
   `WorldLocations`. Replaced it with an authored registry resource and updated
   the route adapter to consume that same registry. Adding a location no longer
   requires modifying either script.
2. Runtime session startup redundantly called `ensure_technique()` for six
   techniques already present in the authored catalogue. Removed that startup
   augmentation and its six redundant preloads. A missing authored technique is
   now a registration failure rather than something startup silently repairs.
3. Provider coverage previously had no common, bidirectional inventory contract.
   Added metadata and read-only adapters for 52 active providers across the five
   locations, plus one explicitly disabled inherited provider. Both metadata →
   scene and scene → metadata are checked. No stale active paths or duplicate
   active provider IDs were found in the validated current scenes.
4. A world scene being present is not proof all catalogue content is playable.
   Explicitly recorded the content delivery gaps below. New unplaced opponents,
   techniques or requests fail QA unless individually documented.

## Explicit exceptions and unfinished content

- River inherits `World/ManilloTrader` from the development outpost template.
  It has no economy context and is intentionally not a River trade provider.
  Validation requires it to remain invisible, `PROCESS_MODE_DISABLED`, with its
  blocking collision shape disabled. Activating it without proper registration
  fails the contract.
- Outposts inherit a Beach fish-zone resource. Their root `_enter_tree()` binds
  the registered location's fishing spot **before** child `_ready()`. Validation
  checks the canonical location context and registered spot; existing runtime
  world-location QA checks the resulting live scene. The inherited editor value
  is not a second population authority.
- Ten opponents have authored roster/acquisition/debug content but no physical
  encounter in this five-location slice: `ash_champion`, `dock_bruiser`,
  `gearwright`, `highland_keeper`, `lantern_gambler`, `marsh_keeper`,
  `pier_apprentice`, `storm_captain`, `tide_oracle`, `wandering_sage`.
- `structure_fighting` and `snag_escape` have authored capability/prerequisite
  data, but Structure Hunter currently teaches only `read_structure`. Delivery
  of those two world lessons remains incomplete. This pass does not add lessons
  or change gameplay. These are named exceptions, not assertions of reachability.

Exceptions live in the validation manifest, carry a reason, must reference real
registered IDs, cannot duplicate one another, and fail if retained after the
content receives a world binding. This prevents them becoming blanket exemptions.

## Validation rules

Run `scripts/qa/content_registration_qa.gd` explicitly. Production startup does
not run it. Scenes are instantiated off-tree without executing provider `_ready`
or touching saves, then freed. The suite also verifies no orphan nodes remain.

- Registry entries must be non-null, nonempty and unique within their domain.
- Recursive domain scans find authored leaf resources omitted from registration.
  Aggregate catalogues and nested artwork are distinguished by script type.
- Location scene paths must resolve to PackedScenes with the exact registered
  location context; destinations and equipment gates must reference valid IDs.
- Provider paths, scripts, IDs, types, references and economy contexts must agree
  with their owning scene. Active interactive/request/fishing-zone nodes cannot
  be silently omitted from metadata.
- World contexts cannot grant unrestricted catalogue access or contain no content.
  Shops, trade shops and explicit recipe allowlists must resolve and agree.
- Fish population references, trade inputs/outputs, shop outputs, crafting
  materials/templates, Card Maker inputs/cards, reward items and request objective
  IDs must resolve against their domain registries.
- Opponent/card acquisition/competition resource contracts run with real authored
  card data. Technique and opponent dependency graphs reject cycles and missing
  prerequisites. World request rewards and world treasure/competition IDs resolve.
- NPC scenes, root and GroundPresentation profiles must agree. Default animations,
  directional aliases and animation prefixes must resolve. Existing NPC catalogue
  QA additionally checks atlas frames and ingestion details.
- Acquisition uses a fixed-point search over the actual route adapter and authored
  provider contexts. Every target must produce the declared item. Trade fish must
  exist with positive population weight in currently reachable spots. An item
  cannot unlock its own unavailable source. This checks structural reachability,
  not monetary affordability, player skill or balance targets.
- Negative fixtures cover duplicate content/provider IDs, invalid references,
  unregistered leaves, missing resources/nodes/metadata, prerequisite cycles,
  missing acquisition sources and an unseeded progression chain.

The nine validated early acquisition targets are Baby Frog, Bamboo Rod, Tail,
Crab, Floater, Popper, Angling Rod, Silver Top and Hanger. Existing acquisition,
world-location and fishing contracts continue to cover runtime behavior.

## Expansion workflow

1. **Fishing location:** author `PlayableLocationContext` and a scene using the
   existing location root. Register the context in `location_registry.tres`.
   Add valid bidirectional travel destinations and matching scene travel points.
   Set its canonical spot and equipment gates. Add validation bindings for its
   providers. Run content and world-location QA. No central runtime list edit.
2. **Shop/item provider:** add offers to `all_shops.tres` with valid tackle IDs.
   Create a contextual economy resource with the intended shop/availability IDs.
   Place a merchant, pair its path/context in location metadata, and add its
   validation binding. Offers alone do not make a shop reachable.
3. **Manillo trader:** register recipes in `all_trades.tres`; use canonical fish
   IDs/counts and tackle outputs. Author the context's shop/recipe allowlist,
   place a trader, register its path/context, and add validation metadata.
4. **Fish population:** author FishData and register it in `all_content.tres` if
   new. Add canonical fish spawn entries to a registered spot, with legal weights.
   Register a new spot in `all_content.tres` and assign it to a location if playable.
   A catalogue spot without a playable location is library content, not a route.
5. **Crafting station:** add materials/recipes to the shared crafting catalogue;
   existing stations consume it through the existing session service. Place the
   station and declare its validation binding/catalogue. Independent per-station
   recipe subsets are not currently supported; that would require a separate
   scoped runtime feature rather than pretending metadata grants the subset.
6. **Card opponent:** author/register the opponent, its card IDs/prerequisites and
   acquisition-map source contract. Place an opponent with matching ID/profile
   and add the validation binding. If explicitly future content, add a named
   deferred exception; remove it when placed. Do not use NPC role tags to grant
   an encounter. Acquisition-map reward coverage is a deliberate consistency
   contract with opponent rewards, not an alternate owned-card store.
7. **Fishing Master:** author/register a technique and prerequisites. Place a
   lesson actor whose teacher/technique match, and declare the binding. Reusing
   existing lesson behavior is local; a genuinely new lesson still needs its own
   policy/NPC script. It no longer needs session-service catalogue supplementation.
8. **Card Maker/request/reward content:** append recipes/definitions to their
   existing authoritative catalogues; use valid fish/cards/materials and source
   IDs. Place the corresponding provider/request source and record its binding.
   Extend acquisition planning only where it represents an intended delivered
   progression source; do not use developer access to satisfy reachability.

The only common registration edits are the relevant catalogue, location context,
scene and validation metadata. Adding an already-supported provider type requires
no unrelated gameplay script edits. A new provider behavior requires its own
runtime implementation and a focused validation adapter.

## Verification

Commands use Godot 4.7.2 with `--headless --path . --script` followed by the named
suite. Runtime suites isolate their own user data. Final counts are recorded below.
The default economy suite was also run: its 80/81 result is the expected dedicated
balance failure. The existing `-- --structural-only` mode passes without changing
or hiding the two H12 guardrails. No economy values were edited.

Web build: `& .\tools\mobile\build_mobile_playtest.ps1` (existing Linux builder;
validated PCK/project.binary; does not restart HTTPS).

| Suite (`scripts/qa/` unless noted) | Final result |
| --- | --- |
| `content_registration_qa.gd` | 2149/2149; 52 active providers; no error output |
| `world_location_access_qa.gd` | 586 checks, zero failures |
| `early_tackle_acquisition_qa.gd` | 61 checks, zero failures |
| `world_economy_access_qa.gd -- --structural-only` | 81 checks, zero failures; guardrails remain 22/24 |
| `economy_health_classification_qa.gd` | 30/30; guardrails remain 22/24 |
| `npc_catalog_qa.gd` | 2589/2589 |
| `session_contract_runner.gd`: crafting | 14/14; 36 recipe combinations |
| Same runner: economy foundation / Card Maker | 13/13 / 10/10 |
| Same runner: Triple Triad | 101/101 |
| Same runner: campaign / fresh save | 14/14 / 55/55 |
| Same runner: full fishing | 22950/22950; zero orphan nodes |
| `runtime_lifecycle_qa.gd` | 1832/1832; full fishing 22950/22950 |
| `runtime_lifecycle_qa.gd -- --mobile` | 1052/1052; full fishing 22950/22950 |
| `git diff --check` | Passed |

Known balance alerts remain exactly:
sell-heavy H12 wallet 20975 against ceiling 15500, balanced H12 wallet 10537
against ceiling 8000. The explicit balance failure was observed, not renamed PASS.
Physical iPhone acceptance was not rerun for this data-registration pass.
