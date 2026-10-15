# CODEX HIGH — DEEP SOFTWARE ARCHITECTURE AUDIT

You are the independent principal software engineer/architect for a complex Godot 4.7.2 game, FishingGame. Perform a **deep, evidence-based, read-only architecture audit** of the entire **currently checked-out project**, not only its fishing scene. The user wants a solid foundation before further gameplay/UI development. Think critically; do not merely affirm their proposed solutions.

## Rules

1. NO SOURCE MODIFICATIONS. No refactors, no 'quick fixes,' no changes to project settings or import metadata. Write only audit reports under `audit_reports/software/` and temporary logs there. If a test command might modify saves/data, isolate the test or mark it unsafe and don't run it.
2. First record actual commit identifier or snapshot hash, file counts, Godot version, current main scene UID, launch paths and any uncommitted changes. Use **FRESH6** as the source snapshot for this audit. Record the FRESH6 archive SHA-256 and the current checked-out project tree hash if accessible. A missing `.git/` folder means commit history and source provenance cannot be reconstructed from the ZIP; do not invent a commit ID. Confirm whether the local working copy matches the archive before relying on the snapshot.
3. Treat prior reported green QA as historical signal only. If running tests, record exact commands, environment, completion status, coverage and side effects. Never invent passing checks.
4. Classify every finding as **confirmed defect**, **confirmed architectural weakness**, **measured performance risk**, **hypothesis needing validation**, or **improvement opportunity**; include specific file/line/node evidence and reasoning. Prioritize actual player-facing and future-development impact over style opinions.
5. Do not touch the approved fishing camera or weather appearances. Audit their interfaces and change coupling without modifying their behavior.

## Context / design criteria

Four pillars: MODULARITY, SCALABILITY, PERFORMANCE, EXTENSIBILITY. Also include TESTABILITY / OBSERVABILITY and correctness. The game contains fishing mechanics, encounters, bait/lure, fishing progression, Triple Triad, inventory/economy, crafting, NPC dialogue, quests/campaign, location scenes, weather, tide/current/wind, desktop companion and mobile layouts. Recent QA rounds verified environmental integration through v7 and a user-reported 182/182 live-weather suite after corrected fixtures; v7 source is present in FRESH6. Crucially, FRESH6 `actors/FishingRainVFX.tscn` stores `weather_mode = 2` (Rain Preview), which may prevent automatic weather presentation when this scene is instantiated in ordinary play. Trace actual production ownership and test before recommending a change. The user's current F5 experience differs from the standalone desktop companion UI; the main scene in FRESH6 resolves to `actors/FishingTestScene_V2.tscn`, while desktop has `actors/desktop/DesktopCompanion.tscn`. Verify how shipped companion mode is launched and why F5 differs from desktop in practice.

## Audit investigation workstreams

### 1. System inventory and ownership
- Enumerate autoloads, authoritative domain services, scenes, managers, singleton state, resources and independent modules. Diagram upstream/downstream ownership for time, weather, wind, current, tide, fish ecology, casting, camera, UI, progression, save/restore.
- For each significant game system: public contract, dependencies, source of truth, lifecycle, initialization order, teardown and error behavior.
- Detect duplicate state, circular or implicit dependencies, global lookups, brittle `get_node` paths, dynamic node injection, event subscriptions that survive scene changes, transitive callbacks, and unexpected mutation paths.
- Identify giant scripts/state machines that pose *real* maintenance risk, with extraction seams and regression cost; do not prescribe splitting solely by line count.

### 2. Extension/change-impact exercises — REQUIRED
Trace and score how many files/systems must change for each hypothetical (DO NOT IMPLEMENT):
A. Change the fishing camera's framing/safe bounds independently.
B. Change throw power, casting timing, or lure physics independently.
C. Add a new fishing location with distinct depth, current, fish population and visuals.
D. Add a fourth weather condition or an independent snow/fog VFX implementation.
E. Add a fish species or tackle item and make it purchasable, catchable and savable.
F. Add a Triple Triad rule / new NPC opponent / reward source.
G. Add a new desktop HUD indicator without changing gameplay or mobile behavior.
H. Replace a tuned effect's defaults with an artist-authored configuration resource.
For each: entry point; exact dependency chain; touching points; whether existing implementation requires risky code modification; estimated complexity and regression tests.

### 3. Input, gameplay, view and desktop/mobile boundaries
- Analyze source of truth for input (K/I/A/D and menu actions), modal focus, held-press gating, animation callbacks, scene transitions, pause and desktop passive mode. Distinguish game logic from rendering/UI.
- Explain precisely why F5 in the editor differs from the exported/companion desktop presentation. Inventory launch scenes, bootstrap, viewport embedding, floating/docking shell, export overrides and debug modes. Propose a **canonical desktop development launch** that reproduces shipped UI while preserving direct isolated scene play and mobile-specific launch. No implementation yet.
- Evaluate whether placing wind, weather, fishing availability and contextual current in-game is a presentation choice over common model data, rather than data duplicated across desktop panels and game canvas.
- Check camera-safe-area/hud assertions; report known QA history of fixture-induced camera warnings and remaining real risks separately.

### 4. Persistence, determinism, lifecycle
- Verify ownership and persistence of weather schedules, environmental state, time, travel, saves, unlocks, inventory, in-progress fishing, reload behavior, UI state and cross-location session teardown.
- Explore failure paths: missing nodes/services, startup ordering, mid-transition leave/reenter, save interruption, repeated loading, resource references and stale callbacks.
- Verify manual preview/QA overrides cannot silently leak into real gameplay.

### 5. QA architecture and confidence
- Map tests by module: unit/service, fixture/integration, true in-engine integration, human acceptance. Detect tests relying on private method calls, monkeypatched state, fixed wait time, hidden assumptions, skipped real animations, force-created catches, isolation of save paths, and false positives.
- Evaluate whether QA failures found in v2/v3/v7 repairs show systemic fixture weaknesses. Recommend a fixture framework or contract tests only if supported by evidence.
- Generate a **test-to-system coverage matrix** and a risk-based regression selection strategy for camera/casting/weather/UI changes.
- If Godot executable is unavailable in PATH, on Windows inspect the running Godot process for executable path. Never assume `godot` works as a bare command. Don't run tests that damage user saves.

### 6. Authoring workflow / 'bake good values' tooling
- Inventory exported Inspector settings, `.tres` / `.tscn` overrides, inherited scenes and default values in scripts.
- Evaluate three options for artistic tuning: (1) native saved scene overrides, (2) explicit `Resource`-backed profiles and preset variants, (3) an editor tool/plugin for 'Save Tested Values / Restore Defaults / Save as Preset'. Do NOT favor rewriting `.gd` defaults by default. Define source-of-truth semantics, undo/redo, version control, collision/conflict handling, live preview vs persisted changes, asset sharing, validation and safe revert.
- Propose a narrow proof of concept using one selected effect, with exact scope and risks, to be considered *after* audit approval.

### 7. Operability, build and dependency hygiene
- Inspect import paths, case-sensitivity, export presets, missing UID/resource links, unused modules, orphan scenes, deprecated test harnesses, old backup files, addon packages, data schema/validation and source-control ignore rules.
- Avoid deleting apparently unused assets unless their references and non-code consumers are audited.

## Required evidence outputs

Write the following Markdown files:

**EXECUTIVE_SUMMARY.md:** 1-page bottom line; top 10 risks; explicitly distinguish confirmed defects from speculative issues; readiness verdict and blockers.

**FINDINGS.md:** table with ID (SW-001...), severity (Critical/High/Medium/Low), category, verification status, exact file/path + line/node evidence, reproduction, player/developer impact, suggested low-risk remedy, scope/cost, regression-test evidence, confidence, and deferral option. Explain opposing trade-offs.

**DEPENDENCY_MAP.md:** system map, autoload/source-of-truth registry, event flows, ASCII or Mermaid diagrams. Trace change-impact scenarios A–H with concrete touchpoints.

**TEST_AND_CHANGE_IMPACT_MATRIX.md:** test coverage vs functional feature and realistic change scenarios; untested transitions, recommended tests, false confidence risks, and baseline commands/results.

**DEVELOPMENT_WORKFLOW.md:** canonical F5/export/desktop workflows, safe preview versus production paths, proposed editable profile pipeline, and rollback strategy.

**OPEN_QUESTIONS.md:** only evidence gaps that could materially change prioritization, including need for real Godot profiling.

## Method

Work in passes: (1) enumerate and map; (2) trace key code paths; (3) deep-dive highest-risk coupling; (4) execute safe tests if possible; (5) challenge your own findings for false positives; (6) write traceable reports. Prioritize actual source inspection over blanket search-result counts. Leave the repo unchanged. At completion provide a short summary plus report paths and specific unresolved evidence gaps. Spend High effort on difficult causal analysis, not on generating an enormous repetitive list.

## FRESH6-specific audit checks (required)

- `actors/FishingRainVFX.tscn` has `weather_mode = 2` while `scripts/environment_fx/fishing_rain_world_vfx.gd` maps 2 to Rain Preview. `scripts/world/playable_location_scene.gd` lists this scene as a world-owned FX. Verify whether preview flags persist into normal gameplay, and whether a developer preview mode should be automatically reset or routed through a separate profile. **Do not change it during the audit.**
- Confirm editor F5 run path vs desktop companion including scene/embed/launch arguments, not just existence of two scenes.
- The archive excludes `.git/`, `.godot/` and may exclude output folders. Distinguish source observations from unmeasured runtime/import behavior. `export/index.wasm` and `export/index.pck` are present but are derived artifacts and must not bias code or asset analyses.
