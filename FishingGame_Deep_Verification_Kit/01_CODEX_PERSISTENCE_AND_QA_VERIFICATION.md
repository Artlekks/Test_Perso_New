# CODEX ASSIGNMENT 1 — Senior Reliability Engineer / Adversarial Persistence & QA Verification

You are conducting a deep, independent **evidence-gathering audit**, NOT a production implementation. Use the existing `FishingGame_Audit_FRESH6` project and previous Software Architecture / Technical Artist reports as leads; inspect real source to confirm or refute them. Focus on SW-002, SW-003, SW-004, SW-005 and SW-006 rather than repeating a 530-script inventory.

## Governing safety requirements (absolute)
1. Freeze original FRESH6 baseline; production scripts, resources, settings and artwork remain untouched. Reports only at `audit_reports/verification_persistence/`.
2. For **any** Godot import, test, instrumented run or crash simulation, first create a **full disposable project clone outside the baseline** with a unique identifier. All cloned test data must be synthetic. Never use normal `user://` without verifying its absolute OS path.
3. Before any autoload executes, establish unique isolated save namespace for the clone; in a separate verification step confirm `ProjectSettings.globalize_path("user://")`, each session/autoload persistence path, configured custom paths, and no fallback to ordinary game saves. Record exact results. If the isolation proof fails, do not run state-mutating tests. No deleting or overwriting user's live saves.
4. Restrict failure injection and any process termination to the disposable Godot process and its own sandbox files; do not kill the user's running editor or processes. Never clear real AppData folders. Never elevate privileges to work around safeguards.
5. Use installed Godot 4.7.2 stable discovered from the local environment; never assume the `godot` CLI is on PATH. Godot launch/import can create `.godot`; only do so inside disposable clone.
6. Keep the frozen workspace read-only except Markdown reports. No refactors, no improvements automatically applied, no silent test-assertion loosening. Temporary test harnesses in the disposable clone must be identified and excluded from baseline findings.
7. Be exact about what was run and what was not. A controlled fixture cannot certify natural animation/physics/visual play. Include exit code, logs, test data path and reproduction steps.

## Questions to settle

### A. Verify the isolation envelope before anything else (SW-005)
- Trace autoload creation, `WorldLocations`, `GameClock`, session composition, and each save authority, including `session_test_fixture.gd`, game_clock QA and legacy suites.
- Map all `user://`, custom-file, and OS data directory writes; distinguish synthetic test save roots from live saves.
- Propose one early isolation contract that all future QA must assert. Prove the contract in a cloned smoke test without touching ordinary save data. Determine exactly which QA runners are safe/unsafe now.
- Distinguish suite names/individual checks from test coverage; classify U/F/I/A/P and any private completion/test defaults.

### B. Prove or refute catch-journal vulnerabilities (SW-002)
- Inspect `scripts/fishing_catch_repository.gd`, `scripts/fishing_save_integrity_service.gd`, `scripts/fishing_inventory.gd`, `scripts/fishing_progress.gd`, and existing save interruption QA.
- Design controlled failure injection at each write boundary, including failed first store, failed second store, **retry without recreating objects**, retry after restart, repeat failed recovery, and **new catch while previous journal is pending**.
- Verify whether the journal is cleared too early, overwritten, or recovery wrongly considers an in-memory applied ID durable. Assess catch exactly-once behavior, progress/inventory consistency and crash/restart effects. Preserve synthetic before/after state and logs.

### C. Prove or refute file robustness and cross-storage failure paths (SW-003/004)
- Trace direct JSON writers for inventory, progress and rewards; compare existing staged/backup design in clock and Triple Triad persistence.
- Use a disposable clone to test truncated/invalid synthetic save files and controlled interrupted writes. Preserve evidence; do not destroy only copy of fixture data. Differentiate write-failure returns, power-loss speculation and actual terminated-process result.
- Trace crafting, sale/exchange, cooking and other cross-domain transactions; choose **one representative high-risk operation** for a first interrupted-commit reproduction. Identify phase boundaries, journal availability, rollback persistence and recovery after a second restart. Don't create a universal transaction framework.
- Identify compatibility/migration and ordering hazards in a prospective fix.

### D. Establish real coverage limits (SW-006)
- Contrast untouched scene/runtime settings with patched QA fixture settings (especially `FishingRainVFX.tscn` mode 2 vs Auto). Verify at least one original-production-configuration smoke in a sandbox if safe.
- Distinguish deterministic QA contracts from player-driven casting, animation, physics, weather transitions, and true shell input. Do not claim 182/182 entails full acceptance.

## Deliverables (Markdown under audit_reports/verification_persistence/)
1. `ISOLATION_PROOF.md`: exact OS sandbox paths and per-service routing, PASS/FAIL safety gates, engine and commands. If blocked, record precisely why and refrain from running dangerous tests.
2. `PERSISTENCE_FAULT_MATRIX.md`: storage domain x failure point x restart x expected/observed state x evidence, including negative tests; label outcomes RUN/STATIC/NOT RUN.
3. `REPRODUCTIONS.md`: fully reproducible step-by-step sandbox experiments, captured logs/exit codes and minimal fixture changes. List inability to reproduce honestly.
4. `QA_TRUTH_MATRIX.md`: suite tier, patch/mock shortcuts, autoload isolation, and untested real-input/visual paths.
5. `RELIABILITY_DECISIONS.md`: ranked confirmed defects, downgraded hypotheses, minimal repair options, existing-save compatibility and verification gates; recommend ONE bounded first implementation task after review.
6. `READ_ONLY_VERIFICATION.md`: before/after hash comparison of frozen original project excluding this audit report directory; list any unexpected differences.

## Completion rules
Work in incremental stages, writing reports as you proceed. Do not overuse context on unrelated features. Do not start production fixes. If runtime safety is uncertain, report the blocker and proceed with bounded static verification rather than assuming safety.
