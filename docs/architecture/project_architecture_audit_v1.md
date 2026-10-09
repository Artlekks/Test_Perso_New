# Project Architecture & Technical Debt Audit v1

Date: 2026-10-09. Current project, Godot 4.7.2. Scope: architecture, authority, ownership, persistence, expansion and QA. No camera, input mapping, UI styling, grounding, collision policy, progression requirements or balance tuning changes.

## 1. Executive summary

**15 findings: 1 P0, 9 P1, 5 P2, 0 P3.** Three finding groups received localized fixes: configured save-path ownership, inventory subscription ownership, and QA fixture ownership/hidden orphan cleanup. Seven broader P1 findings remain open. P2 findings are staged recommendations, not claims that their current behavior is broken.

The most important demonstrated defect was `FishingInventory.reset_inventory`: an inventory configured with a custom save path deleted the default save. The companion progress reset checked the default path before deciding whether to delete its configured file. Both now honor their own configured path. Tests use a disposable userdata namespace and compare default save bytes.

The largest future bottleneck is the composition boundary. `FishingSessionServices` combines production composition, content registration, startup QA, debug UI and numerous domain-specific forwarding APIs. Triple Triad has useful internal controllers, but persistent deck configuration still has different interpretations in the UI, State API and integrity layer. A seven-profile fixture reproduces that mismatch.

Several suspected duplicates are **not** competing authorities: the generic inventory facade delegates to domain stores; gathering uses the item backbone in production; the live FishZone resolves the authoritative WorldLocations spot; economy config deliberately overrides historical source prices; Developer access is transient. Preserve those boundaries.

The structural regressions are green. Dedicated economy guardrails remain **22/24** with both H12 ceilings exposed. No save schema was changed. A validated Linux/WSL Web rebuild is required and performed because production adapter/save-reset files changed; HTTPS stays running.

## 2. Current architecture and coverage

### Inventory and entry points

The tracked-file inventory during this audit contains **2,326 files, 418 GDScript files, 127,767 GDScript lines, 122 scenes and 474 `.tres` resources**. Lines were measured in the working tree during inspection. Counts include QA and tools/content, not just shipping gameplay, and exclude the new untracked report/QA files. This pass adds two executable QA scripts.

Production script sizes show where responsibilities concentrate:

| Script | Lines at audit | Concrete responsibility mix |
|---|---:|---|
| `scripts/encounter.gd` | 3,505 | Bite/hook scheduling, fight lifecycle, pressure, landing and several technique state machines |
| `scripts/fishing_session_services.gd` | 2,302 | Service composition, QA bootstrap, content augmentation, persistence binding, gathering feedback and domain facade |
| `scripts/fishing.gd` | 2,164 | Input/phase orchestration, scene bindings, camera/view coordination, presentation events and service forwarding |
| `scripts/bait_V2.gd` | 1,929 | Physical bait motion, water/current/line behavior and presentation |
| `scripts/triple_triad/triple_triad_deck_setup.gd` | 1,840 | Deck editing/navigation/rendering, legality, saved-profile loading/sanitizing/writing |
| `scripts/fishing_menu.gd` | 1,803 | Shared menu shell with extracted equip/data/hints/help controllers |
| `scripts/beach_crafting_service.gd` | 1,409 | Craft evaluation, generated lure properties, runtime-resource registration and persistence |

Size alone is not a defect. Findings below depend on the responsibilities and call paths, not a line-count threshold.

`project.godot` owns the input mappings and the single `WorldLocations` autoload. Desktop enters `actors/FishingTestScene_V2.tscn`; the `mobile_portrait` feature selects `actors/mobile/MobilePortraitHarness.tscn`. `GameplaySceneRoot.resolve/change_scene_to_file` abstracts desktop current-scene versus a gameplay scene inside the harness. Fishing lazily acquires one root-level `FishingSessionServices`; its pending WeakRef closes the same-frame initialization race. Session children persist through world travel; gameplay actors, fishing/camera nodes and local menus belong to the scene.

### Explicit inspection passes

| Pass | Coverage | Evidence/limits |
|---|---|---|
| 1: inventory/dependency scan | Complete repository-wide inventory of tracked scripts/scenes/resources and textual references | Metrics captured in ignored `build/mobile-web/architecture-inventory.json`; textual absence is not proof of dead code |
| 2: runtime composition/lifecycle | Session, Fishing, Encounter, Caster/Bait, camera ownership, dialogue, persistent scene bindings, dynamically created effects | Current source tracing plus desktop/mobile Compatibility lifecycle stress |
| 3: authoritative content/progression | Locations/routes/providers/populations; economy prices/trades/acquisition; items/gathering/crafting/Card Maker; campaign, cards, mastery, requests | Resource and consumer comparisons; structural route/reconciliation/acquisition regressions |
| 4: presentation/role boundaries | NPC catalogue/ingestion, role metadata, shared profile/family/collider/marker boundaries and previews | Source tracing and grounding/catalogue/collision/interaction suites; no presentation edits |
| 5: persistence/debug/mobile | Domain saves/journals/rollback, reset paths, deck writers/readers, Developer overrides, isolated harness saves, Web build validation | Isolated reproductions, save-interruption QA, Developer/mobile tests; release-template behavior not executed |
| 6: QA/expansion | Startup QA registry, standalone runners, fixtures, shared-resource mutation, orphan cleanup, content scaling | Seven strict orphan checks, repaired recovery fixtures, new ownership/recovery runners, expansion analysis below |

All requested system areas have been inspected at their architecture and integration boundaries. This is **not a line-by-line correctness proof of all 127,767 lines or an asset-by-asset visual audit**. Physical Safari acceptance, release-template debug exclusion, OS-kill/write interruption testing, large synthetic content performance benchmarks and exhaustively proving every legacy file unreachable remain **incomplete**. They are not hidden behind the green totals.

## 3. Findings, ordered by severity

Every recommended regression below is a future test unless explicitly marked implemented/run in section 9 or 11.

### P0-01 — Reset operations violate configured save-path ownership — FIXED

**Files/functions:** `scripts/fishing_inventory.gd::reset_inventory`, `scripts/fishing_progress.gd::reset_all_progress`.

**Evidence:** inventory reset tested existence of `_save_path` but passed `SAVE_PATH` to `remove_absolute`. A custom inventory reset removed an unrelated default inventory file. Progress reset tested `SAVE_PATH` existence, then deleted `_save_path`; when only the custom file existed it left the stale save behind. The isolated fixture reproduced both.

**Effect:** actual save deletion across ownership boundaries; restart can disagree with the reset runtime. This also invalidates the claim that configured QA paths necessarily protect the normal save.

**Fix:** use `_save_path` for both existence checks and deletion. Inventory's existing starter reseed/commit and progress reset semantics are preserved. No schema changes.

**Regression:** implemented in `architecture_ownership_qa.gd`: keep default wallet save bytes unchanged while resetting a custom inventory; reload the custom file; prove starter tackle; delete custom progress without a default progress file.

### P1-01 — Reconfiguration retains subscriptions to former inventory owners — FIXED

**Files/functions:** `scripts/items/game_inventory_facade.gd::configure`, `scripts/beach_gathering_inventory.gd::configure_backbone`, `scripts/fishing_economy_access.gd::configure/configure_item_backbone`.

**Evidence:** these methods assigned replacement sources and connected their signals without disconnecting their old sources. Former inventories still emitted notifications through the newly configured adapter. Explicit null unbind also left old subscriptions active. The economy-access reproducer failed two assertions before its fix (**22/24 ownership checks**, distinct from the balance score).

**Effect:** notifications from the wrong session/store, obsolete counts in gathering events, redundant refreshes and retained dependencies when interfaces are reused. Current production typically configures once, which explains why ordinary travel did not expose this.

**Fix:** disconnect only each adapter's exact owned callbacks before replacing source fields. Reconfiguration to the same source remains idempotent; null configuration releases subscriptions. No transaction/access evaluation changes.

**Regression:** old-source emissions produce zero notifications; new sources each notify once; repeated same-source configuration does not multiply callbacks; null unbind removes callbacks. Final ownership suite **24/24**.

### P1-02 — QA can report green while leaking fixtures, then hide ownership errors — FIXED

**Files/functions:** `scripts/qa/fishing_save_recovery_interruption_qa.gd::_test_player_inventory_restart`; orphan-cleanup loops in `fishing_fight_camera_tracking_qa::run_existing_regressions`, `world_location_access_qa::_finish`, `world_actor_collision_qa::run`, `fishing_presentation_current_polish_qa`, `runtime_economy_reconciliation_qa::run`, `runtime_economy_telemetry_qa`, and `world_economy_access_qa`.

**Evidence:** seven runners freed every newly observed orphan without proving which fixture owned it. The explicit save-interruption suite passed **23/23**, but teardown found **two** detached `PlayerItemInventory` Nodes. `_test_player_inventory_restart` assigned `inventory = null` and `restarted = null`; Nodes are not released by dropping the variable.

**Effect:** falsely clean test shutdown and weak lifecycle guarantees as fixtures expand. Global orphan scavenging can erase the evidence needed to find the creator defect.

**Fix:** those seven loops now report a failing assertion containing the orphan ID; they do not free unknown nodes. The recovery test frees its two exact local Nodes before constructing the restart replacement. `fishing_save_recovery_runner.gd` provides isolated execution with strict final orphan validation.

**Regression:** recovery remains **23/23**, orphan count **2 → 0**; all seven strengthened runners pass without scavenging. Existing strict lifecycle fixtures remain green.

### P1-03 — Session composition and startup QA are one large dependency hub — OPEN

**Files/functions:** `scripts/fishing_session_services.gd::initialize/_load_debug_qa_dependencies/is_ready` and its domain forwarding methods; `scripts/fishing.gd::_ready`.

**Evidence:** the 2,302-line session builds inventory, economy, dialogue, mastery, campaign, crafting and other services; loads a large `DEBUG_QA_PATHS` registry; runs numerous suites synchronously inside initialization; owns feedback/debug layers; exposes teacher-specific QA getters. `_initialized` is published before composition finishes, while readiness separately checks assembled services. Debug dependency health is all-or-nothing for that registry. Fishing copies many session dependencies into local fields.

**Effect:** adding a feature/master expands a central class and startup work. QA order and content mutation can become initialization preconditions. Independent domain testing requires reproducing significant unrelated setup.

**Recommendation:** keep the current singleton and ownership behavior, but extract composition modules by domain. Introduce explicit initialization status and a separate development QA runner that observes completed production composition. Keep the compatibility facade during migration; do not replace it with another singleton per feature.

**Regression:** production bootstrap with QA disabled, intentionally broken QA dependency, same-frame singleton acquisition and replacement loadout teardown; verify gameplay service readiness independently of suite readiness. Release/debug startup timing and retained script resources should be measured, not inferred.

### P1-04 — Authored mastery catalogue can be repaired by runtime/QA mutation — OPEN

**Files/functions:** `scripts/mastery/fishing_mastery_technique_catalog.gd::ensure_technique`; session `initialize` registration block; `fishing_tide_sense_qa`, `fishing_deep_water_control_qa`, `fishing_surface_control_qa`, `fishing_landing_technique_qa`, `fishing_read_fish_sign_qa`, `fishing_one_with_nature_qa`; several `scripts/mastery/*_qa.gd::run` methods.

**Evidence:** the authored `data/bof4/mastery/all_techniques.tres` already contains the 15 technique entries, including the six separately ensured by the session. QA receives shared catalogue resources and calls `ensure_technique`, which appends when missing. Today those calls are normally no-ops; removing a registration would let an earlier runtime/QA call reconstruct it in memory, changing what later checks see.

**Effect:** data completeness becomes test-order dependent and missing authored entries can be masked. More masters require editing registration and startup QA code in addition to content.

**Recommendation:** authored catalogue is authoritative and immutable during play/validation. Validate missing entries as errors. Tests that need synthetic techniques must duplicate/build their own catalogue. Retire incremental registrations only after tests prove every resource-only consumer sees the same catalogue.

**Regression:** compare catalogue IDs before/after every suite; remove a required entry in a private fixture and require failure, rather than automatic augmentation; run suites in different orders. Not implemented here.

### P1-05 — Deck profile truth is split between UI and backend — OPEN; REPRODUCED

**Files/functions:** `scripts/triple_triad/triple_triad_deck_setup.gd::_load_profile_count/_save_current_profile/_save_profile_count`; `triple_triad_state_api.gd::_build_deck_profiles/_active_profile_index`; `triple_triad_save_integrity.gd::_audit_player_decks`.

**Evidence:** deck UI permits up to **50** profiles and derives count from saved metadata/keys. State API and save integrity independently use `PROFILE_COUNT = 6`. A disposable save with `profile_count=7`, `last_profile=6`, `deck_ids_7` produces **UI count 7, API count 6, API active index 5 rather than 6**. Integrity's loop limit is also 6. The deck UI writes schema version 2; integrity still carries its own deck version constant.

**Effect:** genuine divergent snapshots and incomplete auditing for profiles beyond six. Persistent state depends on opening the UI to sanitize it; a future non-UI consumer/minigame cannot rely on one deck contract.

**Recommendation:** extract a shared DeckProfileStore owning count, IDs, active profile, migration and persistence. UI submits edits; State API and integrity read the same store. Preserve existing IDs, files and legal deck behavior during migration. This is a broader writer/reader boundary change, deliberately not a quick clamp edit.

**Regression:** 5/6/7/50-profile saves, active profile above six, legacy index conversion, deletion/restart, backend legality and UI confirmation parity. Reproduction artifact: `build/mobile-web/architecture-deck.stdout`.

### P1-06 — Crafting rollback is not crash recovery across its three stores — OPEN

**Files/functions:** `scripts/beach_crafting_service.gd::craft/_restore_craft_transaction/save_to_disk`.

**Evidence:** crafting persists generated records, then player material inventory, then fishing inventory. On a returned failure it restores all snapshots and rewrites stores. There is no durable pending craft transaction spanning those steps, unlike `FishingCatchRepository` and `FishingCardMakerService`, which explicitly journal recovery.

**Effect:** process termination between successful writes can leave crafted records/materials/owned tackle disagreeing. A returned-error rollback cannot run after process death. This is a demonstrated structural gap; no claim that a real player's craft save was corrupted in this pass.

**Recommendation:** add an idempotent pending craft journal at the crafting transaction boundary, with a stable transaction ID and defined replay/rollback rule. Reuse the catch/Card Maker recovery pattern rather than introducing a general speculative transaction framework.

**Regression:** restart after each write boundary and before journal clearance; exact one lure/one material debit; unchanged crafted properties and loadout repair. Current recovery QA covers catch/Card Maker, not these craft kill points.

### P1-07 — Domain save durability and unsupported-version policies are inconsistent — OPEN

**Files/functions:** `scripts/fishing_inventory.gd::initialize/load_from_disk/save_to_disk`; `scripts/fishing_progress.gd::load_from_disk/save_to_disk`; `scripts/items/player_item_inventory.gd::load_from_disk/save_to_disk`; `scripts/beach_crafting_service.gd::load_from_disk/save_to_disk`; `scripts/fishing_unlock_state.gd::load_from_disk/save_to_disk`.

**Evidence:** several stores open the final JSON path directly with `FileAccess.WRITE`. Progress/inventory/unlocks reject a newer version, but initialization/callers do not establish a shared read-only/quarantine session state. Player items and crafted-record loading do not reject future schema versions. Triple Triad separately has preflight backup restoration/checkpointing. `save_all_fishing_state` reports durability but is a sequence of domain commits, not one atomic save.

**Effect:** truncated primary files and older builds rewriting newer schemas are risks; multi-domain durability differs by feature. Catch journals protect the catch operation, not every field in every overwritten file. No OS-kill/file-truncation experiment or downgrade acceptance test was performed here.

**Recommendation:** shared atomic file-write utility with temporary file, validated replacement and last-known-good backup; explicit load outcomes (fresh/migrated/invalid/future) that can prevent mutation until recovery. Preserve each domain's schema and ownership initially. Avoid treating unreadable saves as fresh starts that silently overwrite evidence.

**Regression:** corrupt primary + valid backup, failure before/after replacement, disk failure, future version preservation, Web filesystem sync and clean migration. This staged work is wider than the fixed reset-path defect.

### P1-08 — Location provider identity relies on parallel metadata and scene paths — OPEN

**Files/functions:** `scripts/world/playable_location_context.gd`; `world_location_service.gd::context_belongs_here/get_reachable_world_data`; `scripts/progression/economy_runtime_route.gd::provider_exists/audit`; location resources and their provider nodes.

**Evidence:** each location stores parallel `economy_contexts` and `economy_provider_paths` arrays, while the provider scene node also stores its context. Matching depends on array index, exact `World/...` path and shared Resource identity. Current code correctly diagnoses missing/mismatched providers and current route QA is green; expansion still requires synchronizing these pieces.

**Effect:** scene renames or insertion at one array index can invalidate a merchant/trade source and acquisition reachability. Repeated provider-scene instantiation in offline route audits is also a setup cost.

**Recommendation:** authored provider-binding records pairing stable provider ID/context; scene registration validates those IDs against the authoritative location definition. WorldLocations remains the runtime authority. Replace the parallel representation through a validated adapter, not destination-scene special cases.

**Regression:** reorder providers, rename/reparent scene nodes, duplicate provider IDs, missing context and valid zero-destination state; runtime and simulator must resolve the same sources. Do not invent fallback destinations.

### P1-09 — Legacy debug entry points lack the release guard used by Developer Mode — OPEN

**Files/functions:** `scripts/fishing.gd::_ready`; `scripts/fishing_debug_controller.gd::configure/is_toggle_event/open/_on_reset_fishing_progress_requested`; `scripts/fishing_debug_menu.gd::handle_input`.

**Evidence:** Fishing constructs/configures the debug controller unconditionally. It instantiates its menu/regression harness and supplies debug settings to Encounter. F10 detection/open have no `OS.is_debug_build()` guard; the legacy menu handles destructive Shift+R reset. The newer `DeveloperPlaytestService.set_enabled` and campaign guide input do have debug guards, and grants additionally require an authorized isolated save. These are inconsistent entry boundaries.

**Effect:** release runtime depends on debug implementation and exposes a code path to development-only tools unless another packaging layer excludes it. The current mobile export intentionally uses `--export-debug`; preserving that workflow does not establish release safety.

**Recommendation:** explicit development capability at composition/input and destructive command boundaries; keep null/default debug settings compatible with normal Encounter behavior. Move the heavy regression dependency outside production composition. Do not silently change the approved development F10 workflow in this audit.

**Regression:** release-template F10/reset rejected, normal catch recording unaffected without a debug controller, debug mobile F10 preserved and loadout grants still isolated. **Release-template execution remains incomplete**; this finding is proven from the unguarded code path, not a claimed release-device reproduction.

### P2-01 — Fishing lifecycle coordination remains distributed — OPEN

**Files/functions:** `scripts/fishing.gd::_on_mode_changed/_on_bait_returned/_run_catch_landing_sequence/_resolve_failed_fight`; `scripts/encounter.gd::_on_bait_landed/_on_bait_returned` and technique reset/cancel methods; `scripts/fishing_fight_lifecycle.gd`; Caster/Bait callbacks.

**Evidence:** macro fishing phase, fight lifecycle, cast existence, presentation state and individual technique phases have different legitimate owners. Coordinator callbacks explicitly cancel/reset several of them together. They are not automatically duplicate truths; the coupling is the number of reset sites and sequencing requirements for adding another outcome/technique.

**Effect:** future states require coordinated edits to input, Encounter and presentation. Green camera/landing tests must remain the migration contract.

**Recommendation:** document the transition contract first, then extract small outcome/technique coordinators consuming existing events. Keep physical bait authority and camera ownership unchanged. Regression should enumerate every exit/cancel transition, repeated cycles and pending callbacks. No fishing refactor performed.

### P2-02 — Cross-domain integration discovers concrete scene implementations — OPEN

**Files/functions:** `scripts/progression/playable_campaign_progression_director.gd::_find_triple_triad_game`; `scripts/triple_triad/triple_triad_fishing_salvage_bridge.gd::_try_bind_repository/_try_bind_caster`; `scripts/economy/fishing_card_maker_service.gd` card facade calls; `scripts/mastery/fishing_master_lesson_npc_base.gd::_bind_runtime`; `scripts/world/playable_location_scene.gd::_enter_tree`.

**Evidence:** the campaign discovers `TripleTriadGame` by name, Card Maker calls card methods on that facade, lessons locate fishing/Caster runtime, and the location root assumes `World/FishZone_V2`. `GameplaySceneRoot` already fixes desktop/mobile hosting, but it does not remove concrete child-name contracts.

**Effect:** another minigame, additional zones or a different scene hierarchy needs adapters and otherwise unrelated code changes. The fishing-to-card bridge is a useful boundary; fishing mechanics do not need to absorb card implementation.

**Recommendation:** bind typed/narrow capabilities at scene composition (catch stream, card acquisition, lesson observation, current location zones). Keep optional integrations optional and explicitly report unavailable capabilities. Test minimal scenes, destroyed providers and a second mock minigame.

### P2-03 — Content lookup/preview cost scales by repeated scans — OPEN; UNPROFILED

**Files/functions:** `FishingContentCatalog.get_fish_by_id`, `FishingTradeCatalog.get_recipe_by_id/get_all_recipes`, `BeachCraftingCatalog.get_recipe`, `NPCCatalog.get_entry`; `scripts/npc/npc_catalogue_preview.gd::_ready`; `scripts/progression/early_tackle_acquisition.gd::_target_snapshot`.

**Evidence:** several ID lookups scan arrays; trade list retrieval rebuilds/sorts a filtered list; acquisition guidance scans species across spots for each requirement; catalogue preview eagerly instantiates every catalogue actor. Card/acquisition/item catalogues already have caches, so there is no need to invent a new universal database.

**Effect:** adding hundreds of entries raises repeated lookup/setup work, particularly in catalogue preview and composed guidance. **No current FPS regression or measured performance bottleneck is claimed.** Grounding/camera per-frame updates are not changed.

**Recommendation:** benchmark expanded content, then use validated ID indexes and invalidation at existing catalogue boundaries; page preview actors instead of loading every actor. Regression: same ordered results, duplicate IDs rejected, cache invalidation, bounded preview instance count. Not run with synthetic 100/300/200-entry content.

### P2-04 — Progression guidance and the simulator retain curated metadata — OPEN

**Files/functions:** `data/progression/early_tackle_acquisition_v1.json`; `scripts/progression/early_tackle_acquisition.gd::_target_snapshot`; campaign director constants/plan; `economy_progression_simulator.gd` cooking/card-rate constants and profile generation; `economy_runtime_route.gd::targets/price/population`.

**Evidence:** acquisition plan stores item/source IDs plus target/provider display labels. Actual trade requirements/prices are resolved from authored sources, correctly. The simulator now reads real world routes/populations/prices but explicitly retains pooled bait/card banks and rate/hour assumptions. Campaign-specific opponent/event IDs are also curated in code.

**Effect:** changing an authored item name/provider can leave guidance copy stale; expanded campaigns require editing both content plans and special-case evaluators. Simulator assumptions may drift from live cooking configuration unless intentional differences are recorded.

**Recommendation:** resolve presentation labels and output identity from source resources; keep milestones/order as authored campaign data. Maintain an explicit model-assumptions contract for intentionally approximate simulation rates. Do not make the simulator progression authority or convert design assumptions into runtime gates.

**Regression:** rename item/provider in a private fixture and compare guidance; validate source/output ID agreement; report configured-vs-modeled recipe quantities. Existing 22/24 balance alerts must remain visible.

### P2-05 — Mobile hosting policy is identified by node names/global settings — OPEN

**Files/functions:** `scripts/mobile/mobile_portrait_harness.gd::_ready/_node_added/_exit_tree`, `RESPONSIVE_WINDOWS`; `scripts/developer_playtest_service.gd::can_mutate_test_save`.

**Evidence:** harness selects a global userdata namespace in `_ready`, reparents persistent session layers into a SubViewport, and adapts selected windows through a hardcoded node-name allowlist. The exit restoration and grant isolation are tested and currently work. A new shared window still needs its name registered; changing save namespace after existing session services were composed would not reload those services.

**Effect:** future shell/entry-point reuse and another menu can require shell-specific changes. This is not a current phone input or save-isolation failure.

**Recommendation:** choose an immutable save profile before session bootstrap; register responsive-surface capability rather than concrete window names. Preserve shared screens, input forwarding and existing viewport restoration. Test a new menu without shell edits and reject profile switching inside an active session.

### P3 — No proven-safe dead-code removal

A textual reference scan found 32 script candidates with no literal `res://` reference. They include global classes, inherited bases and executable QA entry points; their apparent absence is not proof of non-use. The old display-name `FishingTradeService.get_recipes_for_shop` wrapper and catalogue counterpart have no discovered external textual callers, but remain a public compatibility surface. No script, scene, asset or compatibility API was deleted on that evidence. There is no manufactured P3 count.

## 4. Source-of-truth inventory

| Fact | Authoritative source | Other representations / classification |
|---|---|---|
| Current location/travel eligibility | WorldLocations + `PlayableLocationContext` resources; persistent unlock flags latch legitimate access | LOCATIONS is a code registration list. Developer runtime travel override is separate and explicit; no saved unlock on toggle |
| Provider identity/context | Authored location context plus validated scene provider | Parallel arrays and node resource repeat the association: P1-08 |
| Fish population | Location's `FishingSpotData.fish_population` | FishZone's `get_fishing_spot` resolves current authoritative location; local resource is fallback/explicit debug override, not competing normal population |
| Fish identity/behavior | FishData + spawn entries/content catalogue | Generated item definitions are adapters; stable species IDs connect them |
| Live prices | `data/economy/economy_foundation_v1.tres` through FishingEconomyConfig resolution | Fish/shop/rod/lure reference prices are documented fallbacks; generated item price metadata is derived, not another wallet/pricing authority |
| Fish trade requirements | FishingTradeRecipe resources in `all_trades.tres` | Main row/detail read authored requirements; acquisition plan references recipe IDs; simulator resolves recipe costs rather than manually authoring them |
| Acquisition sources | Acquisition bundles/world acquisition catalogue; real shop/trade sources; early acquisition plan supplies order | Campaign/telemetry/simulator snapshots are read models. Curated labels/model rates: P2-04 |
| Fish/tackle/currencies | FishingInventory | Specimen records preserve physical catches; FishingProgress is lifetime records/points, not spendable stock. GameInventoryFacade delegates by storage kind |
| General items/materials | PlayerItemInventory | BeachGatheringInventory is a production adapter with one-time legacy migration marker; its standalone fallback supports fixtures/compatibility |
| Crafted lure properties/ownership | Craft records generate runtime BaitData; FishingInventory owns counts | Runtime lure cache is derived; three-store transaction durability is P1-06 |
| Card Maker conversion | Authored Card Maker recipes + journaled service + card acquisition backend | UI quote is derived; no manual UI fish consumption |
| Card quantities | TripleTriad collection backend by stable card ID | Card views and State API caches are derived. Rewards/transfers use journals/ledgers |
| Saved decks/active profile | Existing deck ConfigFile, currently written/sanitized in UI | API/integrity use different profile-count contracts: P1-05; move authority to shared store |
| NPC visuals | Visual profile/SpriteFrames, generated from reviewed ingestion manifest/source sheets | Gameplay role providers are composed separately. Provisional catalogue role tags do not install services |
| NPC casting metadata | `data/npc/world_population_v1.json` → generated catalogue entries | Scene placements are authored; suggested locations/UNCONFIRMED special roles are not binding gameplay assignments |
| Grounding/collider/shadow | Physical actor root + presentation/collider profiles + shared shadow family resources | Family string aliases resolve the same family; no destination-scene Y or camera-relative shadow offset introduced |
| Overhead marker | Fixed actor-relative anchor/profile; icon projection supplied by WorldMarkerAnchor | Screen-space icon placement was explicitly approved; preserve that distinction rather than reverting it |
| Mastery unlocks | Mastery service/unlock save + authored technique definitions | Shared catalogue augmentation is P1-04; lesson-local observation is transient, not another learned-technique store |
| Requests | Request definitions/registry for metadata; domain objective/reward adapters for truth | Accepted flags live in PlayerItemInventory metadata. WorldRequestJournal is a read model, not independent completion truth |
| Campaign progress | Read-only director/policy composing domain snapshots | Plans specify milestones; no second campaign state save or hour-based runtime unlock imposed |
| Developer overrides | DeveloperPlaytestService transient enabled/capability policy | Borrowed card test deck is transient; explicit isolated-save grants are intentionally different from toggle. Legacy debug boundary: P1-09 |

## 5. Dependency/coupling map

```text
project.godot
  -> WorldLocations autoload -> authored location/spot/provider resources
  -> desktop gameplay scene OR mobile hosting shell

GameplaySceneRoot (hosting adapter)
  -> scene replacement on desktop / replacement inside mobile SubViewport

FishingSessionServices (persistent composition root)
  -> domain inventory/progress/catch/reward/unlock/item stores
  -> trade/economy/cooking/prepared bait/crafting/Card Maker
  -> dialogue service/controller
  -> mastery/current/tide/environment
  -> campaign read models
  -> [debt] startup QA, teacher QA reports, feedback/debug surfaces

Scene composition
  -> player/GameMode/WorldInteractionRouter
  -> Fishing -> Caster/physical Bait + Encounter/policies + camera/view
  -> actor role providers -> dialogue bridge / session domain services
  -> TripleTriadGame -> composition root -> backend/session/match/recovery controllers
  -> visual profiles -> GroundPresentation -> family shadow / projected marker

FishingCatchRepository.catch_committed
  -> scene fishing-salvage bridge -> Triple Triad world acquisition facade
Card Maker service
  -> [coupling] scene TripleTriadGame facade methods + journaled fishing debit
Campaign director
  -> read-only domain snapshots
  -> [coupling] named TripleTriadGame discovery
Deck UI
  -> [debt] saved deck ConfigFile; API/integrity separately read/sanitize it

Shared menu/view -> presentation snapshots + explicit service commands
Mobile shell -> shared responsive surfaces + input forwarding
Developer policy -> transient capability overrides; isolated grants are explicit
Telemetry -> observed signals/snapshots -> recorder/report; not progression authority
QA -> fixtures/resources/services (must never repair production catalogue or scavenge leaks)
```

No general NPC visual-to-economy dependency was found in the normalized visual pipeline. Gameplay providers consume their roles/services separately. Existing small pure policy classes and adapters are useful extraction seams; do not replace them with a universal event bus.

## 6. Expansion stress test

| Addition | Mostly data today | Required code/setup / debt |
|---|---|---|
| 10 locations | Location resources, destinations, gear requirements, spots, provider contexts and scenes | Register each in `WorldLocations.LOCATIONS`; exact scene child/provider paths; acquisition/campaign plans and QA route fixtures. Introduce one validated authored location catalogue, preserving WorldLocations authority |
| 100 fish | FishData, spawn entries, content catalogue, tuning entries, optional card/cooking mappings | Linear lookups and content-dependent QA; custom behavior outside existing policies requires code. Do not create one hardcoded branch per species |
| 100 NPC visuals | Reviewed source `.npc.json` + ingestion manifest → frames/profile/normalized scene/catalogue | Review art directions/feet/collider family; role attachment remains separate. Preview currently instantiates every entry. Unmapped special roles remain UNCONFIRMED |
| 20 Fishing Masters | Technique definitions/prerequisites and reusable lesson base | Specialized NPC/policy/QA scripts, dialogue-profile mapping and session QA registration/getters. A lesson observation interface plus data-driven common lesson types reduces repeated binding; novel mechanics still deserve code |
| 300 cards | Stable authored card stats, card/acquisition/opponent resources | Current portrait atlas has finite grid capacity; more art/atlas configuration is needed, not just `card_count += 300`. Validate legacy/stable IDs and acquisition coverage. Deck backend/UI split should be repaired first |
| 200 recipes | Trade/Card Maker/crafting recipe resources | Catalogue lookup, generated-lure evaluation and menu iteration scale; fixed crafting ingredient/property model does not encode every possible future recipe. Keep schema limits explicit; add domains through service boundaries, not recipe-ID switches |
| Another minigame | Shared dialogue, inventory facade/transactions, requests and responsive UI can be reused | Session named FishingSessionServices, campaign/card discovery and concrete scene contracts are not minigame-neutral. Add a capability adapter/composition module first; do not couple the new minigame to fishing internals |

These are reasoned expansion traces, **not executed synthetic content/load tests**. Adding authored entries often also requires deliberate integrity/QA expectations; those assertions are contracts, not automatically bad duplication.

## 7. Save/runtime safety and lifecycle

Session services own persistent domain state; scenes own physical bait, camera, actor role sources and local UI. Previous lifecycle fixes remain intact: pending singleton WeakRef; explicit loadout unbind; source-dialogue close; session layer restoration in mobile. Campaign's cached TripleTriadGame pointer is checked with `is_instance_valid`; it is not a second card owner.

CatchRepository writes a pending catch journal before progress/inventory mutation, tracks transaction IDs and replays recovery. Card Maker journals fish-to-card conversion and distinguishes already delivered versus rollback. Triple Triad resolution/transfer/world rewards use journals/ledgers plus integrity backups. These mechanisms must remain domain-specific authorities. They do not make every other JSON write atomic (P1-06/07).

Craft runtime Resources are regenerated from persistent records; acquired physical specimens and authored ResourceLoader caches are expected retention. Telemetry deliberately keeps bounded session ownership and explicit disconnect buckets; event arrays grow while recording by design. Recorded reports are not economy state. Catalogue preview owns its instantiated actors; production does not load the preview scene as a service.

The mobile save namespace is isolated before mounting gameplay; Developer grants check the authorized isolated profile. Toggle alone does not mutate inventory or saved progression. Campaign QA presets are separately labeled destructive save replacement; they are not the normal Developer access override. A unified development composition boundary should preserve that distinction.

Rendered lifecycle stress runs the production route chain repeatedly, fishing/menu/card/developer cycles, weak previous-scene validation, pending callbacks and service identity. Six canonical-boundary samples stabilize at:

| Mode | Structural nodes | Resources | Persistent signal connections | Session instances | Orphans | Timer nodes / active | Active tweens at sample |
|---|---:|---:|---:|---:|---:|---:|---:|
| Native Compatibility | 2,053 | 2,258 | 171 | 1 | 0 | 4 / 1 | 0 |
| Mobile harness, native Compatibility | 2,267 | 2,261 | 42 | 1 | 0 | 4 / 1 | 0 |

Ambient shadow instances fluctuate; landed specimen count intentionally grows. The fixture separates them from structural counts and permits small engine bookkeeping variation rather than asserting a false constant object count. Six route cycles include **48 scene transitions**, 24 casts (12 retrieve/12 land), 66 fishing entry/exit pairs and 12 actual card match starts/closes. It checks final callback/layer/loadout/service teardown and runs full fishing regression after teardown. No orphan scavenging occurs.

Compatibility shader-cache write diagnostics still appear in rendered isolated-profile tests. The previous controlled lifecycle audit proved that changing userdata after renderer initialization can leave cache directories in the prior profile; a profile configured before engine startup avoids the diagnostic under the same permissions. The current traces point to `_save_to_cache` in `drivers/gles3/shader_gles3.cpp`, not a project script exception. No cache settings/log suppression changes. Vulkan-specific behavior and actual Web heap census were not reproduced here.

## 8. QA architecture

Strengths: production route/input/physics fixtures; pure fight/lesson/economy policies; save interruption tests; strict lifecycle ownership assertions; explicit structural-vs-provisional balance classification. The Triple Triad precomposition rejection warning is an intentional backend QA guard test, not proof of an ordinary premature player call.

Weaknesses: startup QA is coupled to session initialization; fixtures/resources are repeatedly assembled in different runners; some tests reach private state to isolate phases; exact content counts can obscure which capability is contractual; shared mastery resources can be mutated; older wrappers silently cleaned orphans. The repaired recovery test proves why ownership must be part of QA success, not a cleanup afterthought.

Recommended fixture migration: isolated save-profile bootstrap, domain-owned fixture teardown and minimal scene composition helpers, introduced one suite at a time. Keep real physics and transition tests. Do not replace behavioral tests with shape/path existence assertions or weaken expected output to accommodate current bugs.

Gaps remaining: deck profiles above six, craft process-kill boundaries, future-version non-overwrite, release debug exclusion, high-content preview/guidance performance and physical Web/Safari lifecycle counts. They have named regressions in the findings rather than invented results.

## 9. Implemented fixes

1. Inventory/progress reset operates on the configured save file. Default production behavior is otherwise identical.
2. Generic inventory facade, gathering backbone adapter and economy access adapter transfer their exact signal subscriptions when reconfigured/unbound.
3. Seven QA runners fail on unexpected orphan nodes instead of freeing unknown owners.
4. Recovery restart fixture frees its two PlayerItemInventory Nodes; new strict recovery runner validates final teardown.
5. New isolated architecture ownership suite exercises save bytes, starter/reload behavior, stale-source events, idempotent configure and unbind.

No content prices/requirements, save version, gameplay UI, camera parameters, role mapping, sprite/shadow/collider positions or mobile input mappings changed. No dead assets were removed. Larger issues in section 3 are intentionally still open.

## 10. Highest-value next three passes

1. **Persistent state and deck ownership.** Value very high; risk medium. First unify deck profile writers/readers without schema changes; then introduce atomic domain writes/future-version protection; then journal craft boundaries. Acceptance: seven/50 profile parity, byte-preserving downgrade rejection and restart at every transaction write boundary. Deliver in separate small changes rather than one save rewrite.
2. **Session composition and development isolation.** Value high; risk medium. Extract domain composition modules behind the current facade, separate QA bootstrap, make initialization status explicit and enforce development capabilities at tool entry points. Acceptance: normal/release session with debug infrastructure absent, independent domain QA and existing singleton/lifecycle behavior.
3. **Validated content/role registration.** Value high; risk low-to-medium. Authored location catalogue/provider records, immutable mastery catalogue and shared lesson observation/role binding; then targeted ID indexes/paged preview if profiling warrants them. Acceptance: add a location and ordinary lesson through data/composition without editing unrelated gameplay; reject missing/duplicate registrations.

## 11. Verification and commands

All commands were run from the project root using the installed Windows Godot 4.7.2 binary. Native executable invocations use `Start-Process -WindowStyle Hidden -Wait -PassThru` with redirected stdout/stderr; exit codes below are actual process codes. Logs use ignored `build/mobile-web/architecture-complete-<suite>.{log,stdout,stderr}`, except ownership (`architecture-final-ownership`) and initial reproductions.

Common executable prefix:

```powershell
$godot = 'C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe'
# Arguments below are passed to that executable, with --path . from project root.
```

| Command arguments | Actual result |
|---|---|
| `--headless --path . --script scripts/qa/architecture_ownership_qa.gd` | 24/24; exit 0 |
| `--headless --path . --script scripts/qa/fishing_save_recovery_runner.gd` | Recovery 23/23; teardown orphans 0; exit 0 |
| `--headless --path . --script scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions` | Camera 168/168; full fishing 22950/22950; fight 24/24, presentation 10/10, stability 27/27; exit 0 |
| `--rendering-method gl_compatibility --verbose --path . --script scripts/qa/runtime_lifecycle_qa.gd` | Rendered native 1826/1826; nested full fishing 22950/22950; exit 0 |
| Same lifecycle arguments plus `-- --mobile` | Rendered mobile harness 1052/1052; nested full fishing 22950/22950; exit 0 |
| `--headless --path . --script scripts/qa/world_grounding_standard_qa.gd` | 1084/1084; exit 0 |
| `--headless --path . --script scripts/qa/world_actor_collision_qa.gd` | 96/96; passive player displacement 0.0, epsilon 0.00001; exit 0 |
| `--headless --path . --script scripts/qa/world_interaction_qa.gd` | 93/93; exit 0 |
| `--headless --path . --script scripts/qa/world_location_access_qa.gd -- --architecture-only` | 579 checks, 0 failures; exit 0 |
| `--headless --path . --script scripts/qa/npc_catalog_qa.gd` | 2589/2589; exit 0 |
| `--headless --path . --script scripts/qa/developer_playtest_qa.gd` | 89/89; exit 0 |
| `--headless --path . --script scripts/qa/mobile_portrait_harness_qa.gd` | 182/182; exit 0 |
| `--headless --path . --script scripts/qa/economy_health_classification_qa.gd` | 30/30 classification checks; guardrails 22/24; exit 0 |
| `--headless --path . --script scripts/qa/fishing_presentation_current_polish_qa.gd` | 194/194; exit 0 |
| `--headless --path . --script scripts/qa/runtime_economy_reconciliation_qa.gd` | 1002/1002 current invariants; guardrails 22/24, both failures printed; exit 0 |
| `--headless --path . --script scripts/qa/runtime_economy_telemetry_qa.gd` | 91/91; exit 0 |
| `--headless --path . --script scripts/qa/world_economy_access_qa.gd -- --structural-only` | 81 checks, 0 structural failures; economy regression groups green; both balance alerts printed; exit 0 |
| `git diff --check` | PASS |

Campaign/fresh-save, structural economy, crafting, Card Maker and Triple Triad checks actually execute in the booted scene/session of those runners: **Campaign Loop 14/14; Fresh Save 55/55; Economy Foundation 13/13; Beach Crafting 14/14 (36 recipe combinations); Card Maker 10/10; Triple Triad backend 101/101; Dialogue 175/175; Item Backend 13/13**. These are bootstrap suite results, not invented standalone CLI tests.

The current reconciliation total is **1002**, not the historical 1029 mentioned in earlier work. This pass did not remove/rewrite reconciliation assertions: its only change is replacing orphan scavenging with a failure. Content-dependent loop counts must be reported as executed, not relabeled to a historical total.

Dedicated balance truth remains:

- Sell-heavy H12 wallet: **20,975**, target **<=15,500**, failed provisional guardrail.
- Balanced H12 wallet: **10,537**, target **<=8,000**, failed provisional guardrail.
- Structural route/source/viability checks pass; no ceiling/price/guardrail changes.

The seven-profile diagnostic was run headlessly with a disposable ConfigFile: UI 7 / API 6 / active index 5 instead of 6. It is evidence of an **open** finding, not a green regression.

Initial defect reproductions intentionally exited nonzero. The first save/subscription probe passed 5/27 before fixes (it dynamically counted stale connections); the final stable fixture uses fixed ownership assertions. The economy-access probe subsequently passed 22/24 before its fix and 24/24 after. Recovery originally passed its 23 domain assertions but failed strict teardown with two orphans; after creator cleanup it passes both. These differing checks are not economy guardrail totals.

Linux Web command: `& .\tools\mobile\build_mobile_playtest.ps1`. The helper uses WSL `FishingGameMobileBuild`, Godot `/opt/fishing-mobile/Godot_v4.7.2-stable_linux.x86_64`, the unchanged `Mobile Portrait Web Playtest` preset and validation before publication. **Final rebuild succeeded: PCK 32,005,236 bytes; `project.binary` 9,944 bytes with `ECFG` header.** No HTTPS restart. Physical Safari refresh acceptance is not performed by this audit.

## 12. Complete changed-files manifest

Production (5):

- `scripts/fishing_inventory.gd` — configured reset deletion path.
- `scripts/fishing_progress.gd` — configured reset existence check.
- `scripts/items/game_inventory_facade.gd` — transfer inventory subscriptions.
- `scripts/beach_gathering_inventory.gd` — transfer backbone subscription.
- `scripts/fishing_economy_access.gd` — transfer inventory/modifier/facade subscriptions.

Existing QA (8):

- `scripts/qa/fishing_fight_camera_tracking_qa.gd`
- `scripts/qa/world_location_access_qa.gd`
- `scripts/qa/world_actor_collision_qa.gd`
- `scripts/qa/fishing_presentation_current_polish_qa.gd`
- `scripts/qa/runtime_economy_reconciliation_qa.gd`
- `scripts/qa/runtime_economy_telemetry_qa.gd`
- `scripts/qa/world_economy_access_qa.gd`
- `scripts/qa/fishing_save_recovery_interruption_qa.gd`

New QA (4):

- `scripts/qa/architecture_ownership_qa.gd`
- `scripts/qa/architecture_ownership_qa.gd.uid`
- `scripts/qa/fishing_save_recovery_runner.gd`
- `scripts/qa/fishing_save_recovery_runner.gd.uid`

Report (1): `docs/architecture/project_architecture_audit_v1.md`.

Regenerated Web artifacts (2): `export/index.html`, `export/index.pck`. No server, certificate, build-helper, exported JS/WASM or gameplay asset edits. Ignored logs/diagnostic probes under `build/mobile-web` are evidence artifacts, not shipped source files.
