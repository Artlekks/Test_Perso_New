# Full Project Audit — 2026-10-02

## Scope and authority

This audit treats the uploaded `fishing_game_clean_candidate_FRESH(4)` project as the authoritative continuation checkpoint. The goal is not a cosmetic folder reshuffle. The goal is to preserve the current vertical slices while making the project easier to extend, reason about, profile, and debug under three rules: **scalability, modularity, and performance**.

The current project contains three increasingly connected domains: the fishing vertical slice, Triple Triad, and the beach gathering/crafting/economy/item backbone. The correct architectural strategy is therefore evolutionary: preserve stable behavior, make ownership boundaries clearer, eliminate duplicate/unused assets and data, and refactor the highest-risk coordinators by strangling responsibilities out of them instead of rewriting working systems.

The uploaded original was left untouched. All cleanup described here was performed in a separate source-only candidate.

## Current debugger errors

### 1. Item Backend QA — beach material sell values

The screenshot showed:

`Item Backend QA: Beach materials expose sell values through canonical definitions — All five current beach materials must have a positive provisional sell value.`

This was a real data problem. `BeachMaterialDefinition.sell_price_zenny` defaults to `0`, and the new canonical item catalog correctly propagates that value. The five material resources did not contain explicit sell values, so the QA check was doing its job.

The cleaned candidate now defines the intended provisional values:

- Driftwood: 1z
- Shell: 2z
- Seaweed Fibre: 2z
- Iron Scrap: 3z
- Sea Glass: 4z

This is the only intentional gameplay-data change made during the cleanup.

### 2. `Values of the ternary operator are not mutually compatible`

The uploaded ZIP already contains explicit-if replacements in the two recent code paths that were the likely source of the typed ternary reload failure. In particular, the current `beach_crafting_service.gd` and `beach_material_definition.gd` no longer use the problematic typed ternary forms from the preceding edits.

A static scan of the uploaded/current modified scripts did not find another obvious incompatible typed ternary. This strongly suggests the screenshot captured the editor immediately before the latest source fix or while the editor still held a stale parser error. This still needs one clean Godot reload to prove at runtime; no Godot engine binary was available in the audit environment.

## Cleanup performed

### Runtime assets now have domain ownership

The previous tree mixed UI, gameplay sprites, Triple Triad exports, source art, duplicate exports, and authoring metadata. That was a maintenance problem even when runtime references happened to work.

Runtime assets now follow domain folders:

- `assets/ui/fishing_hud/` — fishing HUD textures
- `assets/ui/shared/` — shared UI textures such as distance numbers
- `assets/ui/triple_triad/` and `assets/ui/triple_triad/card_game/` — Triple Triad UI
- `assets/sprites/fish/` — fish atlas/runtime fish sprites
- `assets/sprites/fishing/bait/` — bait/ripple runtime sprites
- `assets/sprites/player/fishing/` — fishing character animation exports
- `assets/sprites/shared/` — shared gameplay sprites

All literal `res://` references were updated. Import sidecars were moved with their assets and their `source_file` values were updated, preserving import UIDs/settings.

The old `assets/triple_triad` runtime folder is gone. `assets/sprites` and `assets/ui` roots no longer contain loose files.

### Authoring/source art is separated from runtime

Editable `.ase`, `.aseprite`, sprite export JSON, dormant reference images, and the unused River environment source are now under `source_art/`, which contains a `.gdignore`.

This is deliberate. The right cleanup is not to destroy editable originals merely because they are not runtime dependencies. They are no longer imported or scanned as runtime content, but remain available when an asset actually needs to be edited or re-exported.

### Documentation/reference data is separated from runtime data

Documentation now lives under `docs/`, also guarded by `.gdignore`. Architecture notes, fishing tuning/reference data, Triple Triad design/audit material, crafting docs, and item-backbone docs no longer sit inside runtime data directories.

The project previously contained 102 generated `.translation` artifacts and CSV import sidecars caused by design CSVs being interpreted by Godot as translation input. Those artifacts were removed. The design/reference CSVs remain preserved under `docs/` where they belong.

### Shared item backbone scripts are grouped

The six new shared item-backbone scripts are now under `scripts/items/`:

- `game_item_definition.gd`
- `game_item_catalog_service.gd`
- `player_item_inventory.gd`
- `game_item_transaction_service.gd`
- `game_inventory_facade.gd`
- `game_item_backend_qa.gd`

All preload references were updated. This gives the item system a clear home instead of adding more generic scripts to the already crowded root script folder.

### Confirmed orphan runtime resources were removed

The audit removed only resources that had zero static references and were not part of a known dynamic directory-loading path:

- obsolete `data/triple_triad/plus_rules.tres`
- four BOF4 trade resources not present in the active trade catalog
- five old fight-archetype prototype resources

The remaining statically unreferenced `.tres` resources are the 20 expected debug/QA profiles loaded dynamically from their debug directories.

### Dormant reusable scenes are retained but labeled as templates

Zero-reference authored scenes that are useful reusable building blocks were not deleted. They moved to `actors/templates/` by domain. This includes fishing snag templates, the beach crafting vertical-slice world template, and Triple Triad world-interaction templates.

That makes their status explicit: they are not current runtime graph dependencies, but they are intentional authoring templates rather than garbage.

## Static integrity results

The cleaned candidate passed the following static checks:

- 0 missing literal `res://` paths
- 0 missing `.import` source files
- 0 duplicate `class_name` declarations
- 0 duplicate function declarations within scripts
- 0 GDScript preload dependency cycles
- 0 duplicate tracked source UIDs
- 0 exact duplicate runtime PNG groups
- 0 unexpected zero-reference runtime `.tres` resources
- main scene UID matches `project.godot`
- 197 GDScripts / 110 unique `class_name` definitions

Content counts remain intact:

- 30 fish
- 11 fishing spots
- 20 lures
- 6 rods
- 179 Triple Triad cards
- 5 beach materials

Every original `.gd` file was compared against the cleaned candidate after normalizing only the asset/script paths that intentionally moved. There are **zero gameplay-script logic differences**. The scene/resource comparison likewise found no behavior changes beyond the five intended material sell values and removal of the ten confirmed orphan resources.

The detailed machine-readable validation is in `STATIC_VALIDATION_2026-10-02.json`.

## Project size / import-surface reduction

The source tree excluding `.git` and `.godot` went from roughly 1,431 files / 23.49 MiB to roughly 1,178 files / 15.96 MiB before this report was added. Runtime/import-facing content is about 1,032 files / 6.87 MiB, with source art and documentation kept outside Godot's runtime scan.

Runtime PNG duplication is now zero by exact hash. PNG count dropped from 206 in the uploaded source tree to 144 total preserved PNGs, while `.import` sidecars dropped from 226 to 144. The reduction is mainly duplicate exports, stale runtime art, and generated/import debris—not working content.

## Architecture assessment

### What is already well designed

The project is not fundamentally spaghetti. Several earlier refactors are doing real architectural work and should be protected rather than rewritten.

The fishing side has meaningful boundaries: `FishingSessionServices` is a composition point, debug responsibilities have their own controller, fish data flows through the journal/menu path rather than being redefined independently in each screen, and the fishing menu has already started delegating page responsibilities. The Resource-driven catalogs are also the right pattern for content-heavy systems.

The shared item/inventory direction is strong. Canonical item IDs, a compatibility facade, an atomic transaction service, an inventory event surface, and explicit migration support are exactly the right way to replace older domain-specific inventories incrementally. This is a strangler migration, which is much safer than a big-bang rewrite.

Triple Triad has broad backend coverage, data-driven cards/profiles, save hardening, world acquisition/integration, and QA infrastructure. Its problem is not a lack of systems; its problem is that too much orchestration and presentation still accumulates in one coordinator.

The dependency graph is also healthier than the file sizes initially suggest: there are no preload cycles and no duplicate class-name/UID conflicts.

## Priority architectural debt

### P0 — finish Pass 2 validation before any new feature work

The cleaned material sell values resolve the concrete QA failure visible in the screenshot. The next action in Godot should be a clean import/reload and execution of the existing Item Backend QA and crafting QA. Do not begin recipe progression or another feature until this checkpoint is green.

The expected first-run checks are listed at the end of this document.

### RESOLVED — transaction event atomicity in the new item backbone

The shared item transaction path now defers inventory notifications while a transaction is in flight. `PlayerItemInventory` and `FishingInventory` buffer their typed change signals, coalesce count/currency notifications to final values, and release them only after the transaction succeeds. Rollback restores the snapshots while the notification batch is still active and then discards the batch, so observers never see the transient state.

`GameItemTransactionService` applies this boundary to consume, grant, exchange, and cross-store material-sale transactions. Item Backend QA now also checks cross-store observer coherence and verifies that a forced persistence failure restores state without publishing item or completed-transaction events.

### P1 — multi-store transactions are rollback-safe, not crash-atomic

The current transaction service takes snapshots and can restore participating in-memory/domain stores if a later operation fails. That is a good prototype-level transaction abstraction, but it is not crash-atomic across multiple persisted stores. A process interruption between writes can still leave stores disagreeing.

Do not overengineer a database for this game. Instead, when the economy expands, give transaction participants a common prepare/commit/rollback interface and add either a tiny transaction journal or one authoritative save aggregation point. That keeps the API scalable without turning the project into enterprise software.

### P1 — `TripleTriadGame.gd` is the largest modularity risk

`triple_triad_game.gd` is approximately 4,720 lines with 159 functions. It is substantially larger than every ordinary runtime coordinator and combines too many categories of responsibility: UI/input, animation/presentation, match-flow orchestration, backend/state APIs, acquisition/progression/recovery, and world-facing integration.

Do **not** rewrite Triple Triad. It already works and has valuable QA coverage. Use a strangler refactor around the existing behavior:

1. extract a `TripleTriadSessionController` for match/flow state transitions;
2. extract a `TripleTriadPresentationController` for UI, input routing, animation sequencing, and screen state;
3. expose acquisition/recovery/world-facing operations through a small facade rather than through the scene coordinator;
4. leave the existing rule/backend services intact;
5. preserve `TripleTriadCardView.tscn` and its existing visual contract.

This one refactor gives the largest scalability/modularity return in the project.

### P2 — keep `FishingSessionServices` as composition, not world gameplay

`FishingSessionServices.gd` is around 808 lines and preloads roughly 40 dependencies. The high dependency count is not inherently wrong for a composition root; a composition root is supposed to know services. The problem is responsibility drift: it is starting to contain beach visit/world-state ownership, UI spawning/coordination, and QA execution in addition to service construction.

Keep one session owner, but move beach/world visit state into a dedicated world-session state object and move QA/debug spawning into debug-only coordination. The resulting `FishingSessionServices` should mostly construct, expose, and wire services.

### P2 — split `BeachCraftingService` by responsibility

At roughly 1,410 lines, `BeachCraftingService` currently spans several different concerns: craft eligibility/domain rules, transaction and persistence coordination, runtime lure reconstruction, QA feel-suite support, and presentation/label formatting.

The safe split is:

- craft domain service — recipes, requirements, craft result intent;
- crafted-lure repository/factory — reconstruction and persistence-facing records;
- debug/QA helper — QA pair/suite generation and diagnostics;
- presentation formatter — human-readable labels only.

The current service can remain a facade while responsibilities move out one at a time, so callers do not need a coordinated rewrite.

### P2 — make the canonical item catalog provider-driven as the game grows

`GameItemCatalogService` currently knows concrete fishing, beach crafting, tackle, and shop data shapes. That is acceptable during migration because it gives one canonical lookup surface immediately.

Once another domain starts registering items, stop adding direct domain preloads. Introduce a small provider/adapter interface where each domain contributes canonical item definitions. The generic item core should eventually know the provider contract, not every gameplay domain class.

### P3 — remove scene-name discovery from domain integration

There are still cross-domain paths using scene-tree discovery such as `find_child(...)` for fishing, Triple Triad, economy/UI integration, and NPC/world interactions. Most of these are not currently in hot per-frame loops, so this is more of a coupling/testability issue than a CPU emergency.

The planned generalized NPC/world-interaction work is the right place to fix it. Give world actors an interaction registry/context/facade and inject the capabilities they need. Avoid creating a global service locator; explicit session-owned capabilities are easier to test and reason about.

### P3 — large fishing coordinators are manageable, but watch growth

`fishing.gd` (~1,962 lines) and `fishing_menu.gd` (~1,800 lines) are large. They are not as urgent as Triple Triad because their responsibilities are already more clearly partitioned and the menu has delegated controllers.

Continue extracting menu pages only when a page has a coherent responsibility of its own. Keep `fishing.gd` primarily as a phase/session orchestrator. Do not split files merely to reduce line count; split when ownership becomes clearer.

## Performance assessment

Nothing in this static audit justifies a performance rewrite. The project has a manageable number of `_process`/`_physics_process` paths, no preload cycles, and earlier lookup caching is directionally correct. The remaining `find_child` / group queries observed are predominantly setup/interaction/coordination paths rather than obvious every-frame scans.

The cleanup does improve **editor/import performance** and project noise by removing generated translation artifacts, duplicate PNGs, unused runtime exports, and source-art imports. It does not prove a runtime frame-time improvement.

Runtime performance decisions should now be driven by the Godot profiler: frame time, physics time, node counts, draw calls, allocations, and hot functions during fishing fights, five-shadow scenarios, menu animation, and Triple Triad rule/animation chains. Do not optimize from script size alone.

## What should *not* be refactored right now

Do not rewrite the fishing state machine, the existing Triple Triad rules backend, `TripleTriadCardView.tscn`, the fish content catalogs, or the save format just because the audit touched their folders. They are stable enough to be boundaries for the next refactors.

Also do not unify every inventory into one monolithic dictionary immediately. The new facade/transaction layer is specifically valuable because migration can happen domain by domain while old persistence remains supported.

## Recommended refactor order

After the cleaned checkpoint passes inside Godot:

1. Make item transaction events commit-atomic.
2. Run/lock Pass 2 economy QA and craft/merchant integration.
3. Extract Triple Triad session flow from `TripleTriadGame.gd` without visual/rule changes.
4. Extract Triple Triad presentation/input/animation coordination.
5. Slim `FishingSessionServices` back to composition/session ownership.
6. Split `BeachCraftingService` domain/repository/QA/presentation responsibilities.
7. Introduce generalized world/NPC interaction capabilities and remove scene-name discovery.
8. Only then continue recipe progression and persistent resource-node/world-state expansion.

The order matters. It strengthens the exact seams that the next features will depend on instead of performing abstract cleanup for its own sake.

## First Godot run — validation checklist

Because the audit environment could not execute the Godot engine, this is the mandatory acceptance pass before this candidate becomes the new baseline:

1. Open the cleaned project and allow one full import/reload cycle. Confirm there are no parser/load errors.
2. Run the main `FishingTestScene_V2` scene. Confirm the main scene opens and the player/fishing world looks identical to the pre-cleanup checkpoint.
3. Run the existing Item Backend QA. The material sell-value assertion should now pass. Confirm the complete suite reaches its expected green result rather than only the one corrected assertion.
4. Run the Beach Crafting QA/feel suite and confirm all existing checks remain green.
5. Open fishing, enter/exit the fishing menu, equip rod/lure/accessory, and verify HUD textures, selectors, animations, fish shadows, bait visuals, and fishing character animations load correctly after the asset moves.
6. Exercise gather → inventory → craft → merchant sell. Confirm material counts, zenny, crafted lures, and save/reload all agree.
7. Enter Triple Triad, verify deck/card UI textures, run a match containing Same/Plus/Combo/Rotate paths, and verify acquisition/save/recovery remains intact.
8. Run the F10/debug QA profiles, especially five shadows and relevant Triple Triad profiles, to confirm the dynamically loaded debug resources still resolve.
9. Save, quit, relaunch, and verify the same player inventory/loadout/economy/crafted-lure state returns.
10. Commit this exact checkpoint only after the above are green. If a load error appears, fix the specific reference; do not roll back the folder structure wholesale.

## Bottom line

The project did need a cleanup, but it does **not** need a rewrite. The core direction is stronger than the messy filesystem made it look. Fishing already has useful service/data boundaries, the new shared item layer is the correct migration direction, and Triple Triad has enough backend/QA coverage to refactor safely.

The two things that deserve immediate architectural attention are the transaction event boundary in the shared item system and the size/responsibility concentration in `TripleTriadGame.gd`. Those are real scalability risks. The random asset placement, duplicate exports, translation debris, mixed documentation/runtime data, and uncategorized new item scripts were cleanup debt; those have been removed from the candidate without changing existing script logic.
