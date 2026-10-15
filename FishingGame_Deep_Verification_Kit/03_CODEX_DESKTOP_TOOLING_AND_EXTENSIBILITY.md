# CODEX ASSIGNMENT 3 — Desktop Launch, Artist Authoring, Extension Contracts

Conduct a targeted developer-workflow/engineering-boundary audit of FRESH6. Use Software SW-007–SW-012, Technical Art TA-004/TA-008, the dependency map and prior reconciled roadmap as leads. Independently verify real files and avoid duplicate project-wide exploration.

## Safety
- Frozen FRESH6 production remains unchanged; report to `audit_reports/verification_workflow/` only. Use a complete disposable clone for any launches, F5/project configuration experiments, editor plugins, or changed scene settings.
- Verify sandbox `user://` isolation before launching. Preserve raw FishingTestScene, approved camera, weather appearance, mobile portrait behavior, docking, floating native title bar, protected gameplay area and actual existing menus.
- Architecture/design findings are not runtime fixes. Do not silently implement a launcher, rewrite UI, or migrate VFX presets in source.

## Investigations

### 1. F5 vs desktop shell: one canonical dev experience
- Trace main scene `project.godot`, `FishingTestScene_V2.tscn`, `actors/desktop/DesktopCompanion.tscn`, `desktop_companion.gd`, window platform adapter, export presets, desktop scripts, SubViewport and menu lifecycle.
- Compare Godot F5, explicit desktop shell scene and existing developer launcher; record visual/UI/action differences. Determine which starts the real companion and which starts only gameplay.
- Evaluate options for a canonical desktop debug launch without breaking separate game scene, mobile/Web startup, and independent QA. Find the minimum number of project/scripts/launcher edits that would be needed, but don't apply them.
- Investigate external Python platform helper, dock L/R, float, title-bar drag, input focus, DPI/layout, compiled export path, path resolution. Distinguish repo-proven gaps from unknown user's existing executable.
- Investigate `UPDATE_ALWAYS` menu SubViewports and whether inactive display updates can be controlled without stale frames; coordinate with actual performance findings before proposing optimization.

### 2. Safe Godot tuning workflows
- Audit current exports, `.tscn` overrides, `.tres` resources and editor write APIs. Distinguish Inspector changes saved in scenes from runtime tweaks not persisted.
- Prototype *design only* for rain `.tres` appearance profile with base → optional location override → temporary preview precedence; weather scheduling must remain independent of art settings.
- Compare three user workflows: native scene saved overrides; a small editor dock Save Preset/Restore/Compare/Undo; optional debug runtime-to-resource export. Explain real Godot 4.7.2 support and safeguards. No generated default .gd rewriting.
- Preserve exact approved values and existing single shared RainImpact texture top-row animation. Avoid schema proliferation for only three effects without proven need.

### 3. Extension stress tests
- Trace required files and change risk for adding one fish, one fishing spot/location, one new weather VFX (no implementation), one new UI modal, a modified casting behavior, and a camera/HUD change.
- Identify explicit contracts vs brittle name scans, implicit timing/node tree ownership, pause/modal stack and runtime registration. Produce a concrete before/after change impact matrix, not general modularity slogans.
- For camera, **do not** recommend decoupling physical bait bounds without proving no gameplay changes. For wind, inspect finalized-path extension seam before advocating a new event bus.
- UI design suggestions may note one desktop control strip and compact in-game wind/weather/current readouts, but are only proposals; do not redesign now.

## Deliverables under audit_reports/verification_workflow/
1. `LAUNCH_MATRIX.md` — entrypoints, commands, actual observations, desktop/mobile/export behavior and assumptions.
2. `DESKTOP_CANONICALIZATION_OPTIONS.md` — at least two options, decision criteria, risks, exact likely touched files, reversible implementation plan.
3. `TUNING_PRESETS_DESIGN.md` — save/compare/revert/undo workflow, ownership/precedence and serialized round-trip acceptance.
4. `EXTENSION_CHANGE_IMPACT.md` — six concrete addition/change exercises with required touchpoints and proposed narrow seam improvements.
5. `WORKFLOW_DECISIONS.md` — ranked repair backlog and ONE recommended first developer-workflow implementation with acceptance/rollback.
6. `READ_ONLY_VERIFICATION.md` — unchanged original sources except audit reports.

Do not implement production changes. Challenge prior audit conclusions with evidence, and mark unsupported assertions explicitly.
