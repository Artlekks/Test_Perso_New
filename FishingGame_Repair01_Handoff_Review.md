# FishingGame FRESH6 — Foundation Repair 01 independent review

Date: 2026-10-14
Source reviewed: FishingGame_Safe_QA_Isolation_Handoff.zip against fishing_game_clean_candidate_FRESH6.zip.

## Verdict

**Request a targeted correction before broad adoption.** The isolated recovery run is supported by the supplied Godot logs and manifest; the infrastructure is not yet a compatible, general QA runner solution.

## Verified strengths

- ZIP integrity passed and file paths are project-relative.
- Diff against FRESH6 contains four modified QA files; four new QA/tooling files. No production gameplay, persistence, scene, or artwork changes.
- Launcher builds unique `qa_sandboxes/FishingQA_<GUID>` with redirected `APPDATA`, `LOCALAPPDATA`, and matching Godot `user://` directory.
- Engine logs record `QA_ISOLATION_PASS`, `QA_ROOT_CLOCK_PATH`, 23/23 recovery assertions, and orphan count 0, across multiple sandboxed runs.
- Two negative preflights reject ordinary game AppData paths before Godot starts.
- Session Contract runner correctly reports failure for Weather Sense 17/22 rather than concealing those five failures; the separate fishing regression reported 22,950/22,950.
- Warnings in recovery stderr include resource UID fallback, Windows certificate store, and deliberately blocked inventory writes; these are visible, not hidden.

## Required corrections

### R01 — Existing SessionTestFixture consumers cannot use the new contract unchanged

The handoff changes `scripts/qa/session_test_fixture.gd` so `mount()` always calls `Isolation.verify()` and `Isolation.verify_root_clock()`. Six other existing runner scripts invoke `SessionTestFixture`, but still change the Godot user directory themselves in `_initialize()`, and do not use the launcher verification protocol:

- `scripts/qa/canonical_portrait_surface_qa.gd`
- `scripts/qa/empty_lure_retrieval_qa.gd`
- `scripts/qa/fishing_camera_hud_stability_qa.gd`
- `scripts/qa/playable_content_delivery_qa.gd`
- `scripts/qa/session_composition_separation_qa.gd`
- `scripts/qa/universal_input_qa.gd`

As written, their legacy run paths are incompatible with the shared fixture's fail-closed contract. Do **not** remove the safety check to make them green. Inventory every caller, migrate it to the pre-start launcher contract, or explicitly document and reject unconverted runners. Test representative converted runs with isolated outputs. Do not run direct QA scripts in an ordinary game profile: their own `_initialize()` user-directory changes may be too late to protect already-initialized autoloads.

### R02 — ValidateOnly unexpectedly changes project.godot

In `tools/qa/Invoke-IsolatedGodotQA.ps1`, lines 45-69, project.godot is rewritten before checking `-ValidateOnly`. This means a nominal preflight dry run permanently changes project settings in the disposable copy. The executable's existence is also checked only after configuration mutation. Make `-ValidateOnly` genuinely nonmutating for the project; for actual runs, use an atomic update and restore the original configuration in `finally`, with a safe interruption/recovery policy. Preserve the unique custom user directory **before** Godot starts. Prevent concurrent runs from editing the same project.godot (exclusive lock or distinct per-run clones).

### R03 — Hardcoded 23/23 completion pattern

`Invoke-IsolatedGodotQA.ps1:25` expects literal `23/23`, which makes valid future test additions fail for reasons unrelated to correctness. Emit a structured suite identity, positive total, actual passed count, actual failed count, and orphan count; enforce passed == total, failed == 0, orphan == 0 and absence of isolation rejection. Do not reduce checks to a generic `PASS` substring or trust process exit code alone. Keep all stderr diagnostics accessible; differentiate known negative-control warnings from unexpected Godot runtime errors.

## Important limitation to preserve

This wrapper protects runs **launched by it** in its explicitly marked disposable project copy. It cannot certify arbitrary Godot F5 runs, direct `--script` launches, absolute paths supplied later by untrusted test code, or the user's existing game save contents. Preserve this scope in documentation.

## Independent Weather Sense issue

The Session Contract runner has 5 Weather Sense failures (17/22); it was not reported as passing. Investigate it as a separately tracked QA/gameplay issue once isolation is stable. Do not change gameplay/weather rules merely to force the test green as part of this infrastructure repair.

## Acceptance criteria for revised handoff

1. The frozen FRESH6 baseline is byte-for-byte unchanged.
2. `-ValidateOnly` leaves project.godot byte-identical.
3. Actual runs restore project.godot after normal completion and reject simultaneous same-copy invocation (and include an interruption recovery strategy).
4. Negative preflights reject unsafe paths before Godot starts.
5. Root GameClock and all known persistence paths resolve inside the unique writable sandbox before fixture mounting.
6. Recovery suite finishes in isolation with all assertions passed and zero orphans; count validation is future-proof.
7. All known SessionTestFixture consumers have an explicit safe run path or are documented as deliberately blocked until migrated; a representative migrated runner is executed.
8. Five Weather Sense failures are not weakened or reclassified.
9. Handoff contains only project-relative changed/new code and concise verification logs, with a rollback procedure.

Only after this focused repair should Foundation Repair 01 be considered broadly adoptable. Next reliability implementation: catch journal lifecycle, not a larger audit.
