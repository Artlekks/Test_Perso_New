# FishingGame — Codex High audit kickoff (FRESH6)

## Frozen source baseline

Use **`fishing_game_clean_candidate_FRESH6.zip`** for both independent read-only audits. SHA-256:

`d86254704232a533e42c7b45085f0b9c48b77c97229d9d863e8e5271a243dcd3`

This ZIP was tested successfully. It includes `project.godot`, all current scripts/scenes/data/assets, Environmental Integration v1–v7 QA scripts and the v7 source after repair. The last user-run v7 QA was **182/182**; we did not rerun Godot. `.git/` and `.godot/` are intentionally absent. These are not blockers for a source audit; they *do* limit history and performance claims. Exported Web binaries may remain in `export/` and should be treated as generated outputs, not source textures.

## Recommended workflow (three separate Codex High tasks)

1. **Software architecture:** Extract FRESH6 into a working project folder. Give Codex High access to that folder and the content of `01_CODEX_SOFTWARE_ARCHITECT_AUDIT.md`. Its only writable output should be `audit_reports/software/` within a separate report copy or allowed report directory. Require a complete system/dependency map and top evidenced findings before it spends time on lower-priority code style.
2. **Technical art:** Use the **same unchanged FRESH6 baseline** (ideally a fresh copy) and `02_CODEX_TECHNICAL_ART_AUDIT.md`. Output only to `audit_reports/tech_art/`. Require raw asset/reference inventories and honest measurement vs estimate separation; no bulk atlasing.
3. **Reconciliation:** Only after the two reports exist, run `03_RECONCILE_AND_PRIORITIZE.md`. Rank fix candidates, include user-facing workflow issues (F5 vs desktop) and propose a single bounded first repair. **No code changes until the user approves.**

To use Codex, extract this audit-kit ZIP alongside or within your local project and instruct it to read the relevant Markdown prompt. Codex High cannot be launched from this chat, so those three tasks must be started in Codex itself.

## Files in this kit

- `01_CODEX_SOFTWARE_ARCHITECT_AUDIT.md` — principal software engineer audit instructions
- `02_CODEX_TECHNICAL_ART_AUDIT.md` — rendering/assets/performance audit instructions
- `03_RECONCILE_AND_PRIORITIZE.md` — critical review and roadmap instructions
- `FRESH6_BASELINE_INVENTORY.md` — ZIP-verified facts, comparisons and evidence limits
- `START_HERE.md` — this guide

## Important observed risks to investigate, not to auto-fix

- Editor F5 launches `actors/FishingTestScene_V2.tscn` while desktop companion has a separate entry point.
- The rain scene saves `weather_mode = 2` (Rain Preview) even though QA forces Auto for integration testing. Determine whether the regular runtime uses this scene as saved, and whether gameplay weather can therefore appear permanently rainy.
- Architecture and technical-art audits should share the same snapshot. Do **not** run the technical-art audit on a repo that the software audit has modified.

## Strict rules

- Read-only source files: preserve working fishing, camera, UI, rain, wind, current, scene settings, save data and artwork.
- Findings must be tied to named source lines/nodes and reproducible evidence; distinguish actual defects from speculation.
- The missing `.godot/` cache is generated on first editor import. That is expected. Missing `.git/` prevents commit-history analysis, not architectural inspection.
- Performance results must state hardware, renderer, resolution, Godot build, test length and actual measurements. Never invent GPU or memory numbers.
- Live gameplay acceptance is still pending. Good QA does not substitute for play feel.

## Quick Codex kickoff text

> Audit the **FRESH6** FishingGame project using the complete instructions in `01_CODEX_SOFTWARE_ARCHITECT_AUDIT.md` at **High** reasoning effort. This is a deep, independent, **read-only** review. Inspect all actual source systems, trace dependencies and verify claims. You may write reports under `audit_reports/software/` only, but make **no** production file changes. Start by verifying project root, FRESH6 snapshot and manifest. Treat existing green QA as historical evidence, not proof of correctness. Deliver the specified evidence-backed reports and a short list of highest-priority issues and unknowns.