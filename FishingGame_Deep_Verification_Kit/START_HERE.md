# FishingGame FRESH6 — Deep Verification Program

Baseline: `fishing_game_clean_candidate_FRESH6.zip`, Godot 4.7.2. Audit results already available: Software Architecture (SW-001–SW-014); Technical Art (TA-001–TA-010); reconciled roadmap. These reports are hypotheses and source traces to validate, not proof of runtime consequences.

## Rules shared by all three Codex assignments
- Open the existing `FishingGame_Audit_FRESH6` workspace. Use Sol Medium as the default. Start a fresh Codex conversation for each assignment.
- Original FRESH6 production sources and artifacts are **frozen**. No changes to `.gd`, `.tscn`, `.tres`, shaders, assets, import configuration, project.godot, or exports in the audit workspace. Reports only under `audit_reports/`.
- Godot may write project caches on import. All engine runs, instrumentation, fixture modifications, executable tests, and temporary patches must happen in a **complete disposable clone outside the frozen audit folder**, not in the frozen workspace. Do not use existing live game saves.
- Before the first engine launch, verify the sandbox `user://` directory, all autoloaded stores, project name, paths, and shared dependencies. Abort any risky test if isolation cannot be proved; never delete, overwrite, or back up live user saves in place.
- Every report must distinguish: source-confirmed fact, reproducible sandbox defect, profiling measurement, hypothesis, and untested limitation. Record engine version, renderer, exact run commands, test/simulation shortcuts, and external factors.
- Do not fix production code during audits. Experimental instrumentation/patches in disposable copies are permitted only if clearly disclosed and reversible; always measure untouched baseline first.
- Preserve approved camera, rain streaks, 5-frame top-row RainImpact, wind/current rendering, sea tint, UI art, and existing fishing behavior.
- Work in phases and save finished findings incrementally. Avoid re-inventorying the whole project; use reports and recheck only relevant paths.

## Sequence
1. `01_CODEX_PERSISTENCE_AND_QA_VERIFICATION.md`: independently reproduce/discount SW-002 to SW-006 and prove QA sandbox boundaries. Highest risk first.
2. `02_CODEX_RUNTIME_PERFORMANCE_VERIFICATION.md`: actual engine baseline; distinguish measured costs from hypothetical render/memory issues.
3. `03_CODEX_DESKTOP_TOOLING_AND_EXTENSIBILITY.md`: F5/standalone parity, artist preset authoring and cross-system extension seams.
4. Upload reports to ChatGPT for independent reconciliation before any implementation. Prefer a small patch queue with explicit regression and rollback over a sweeping refactor.

## Stop conditions
- Any ambiguity about sandbox isolation or real save paths.
- Any experiment requiring destructive edits to the frozen workspace.
- Runtime cannot run in the environment: report the exact blocker and a reproducible user-side protocol instead of manufacturing success.
- Any hypothesis contradicted by instrumentation: retire it, don't optimize it.
