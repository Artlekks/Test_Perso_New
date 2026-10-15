# FishingGame FRESH6 — Foundation Repair 01 corrected handoff review

Date: 2026-10-14
Reviewed package: `FishingGame_Safe_QA_Isolation_Corrected_Handoff.zip`
Disposition: **Core implementation accepted in principle; one final, narrowly scoped launcher correction required before sign-off and deployment.**

## Independently checked

- ZIP passes `ZipFile.testzip()`; paths remain relative to the Godot project. Package contains 10 modified QA scripts and 4 new QA/tooling/documentation files, plus reports and logs. No production gameplay, scene, asset or persistence implementation is replaced.
- The frozen FRESH6 `project.godot` SHA-256 is `AE7233DA7EA3E743A94027F5BAEFD61D94E73ABF7EAD9359987392EA5D23D185`; this matches Codex's reported after-run value. The per-suite logs contain isolation and root-clock markers and structured result records.
- R01: Seven known `SessionTestFixture` entry points now use early isolation verification and root-clock verification. Source diffs were checked against FRESH6. Their tests run inside isolated save roots, with expected failure modes disclosed.
- R02: The launcher has exclusive-lock, original-configuration journal, atomic project replacement, finally-based restoration and `-Recover`. The supplied negative test report documents rejection of unsafe paths and simultaneous execution. `-ValidateOnly` does still create a new sandbox directory and preflight manifest, but does not alter `project.godot`, which satisfies the stated R02 criterion.
- R03: Exact 23/23 is no longer hardcoded. The launcher checks suite identity, total, passing/failing totals, orphan count, Godot exit status and error diagnostics. Deliberate 1/2 failure was rejected.
- Recovery suite: 23/23, 0 orphans, accepted by launcher. Content-delivery: 1453/1453; camera/HUD: 79/79. Other suites disclosed below fail and are not silently passed.

## R04 — BLOCKER for normal launcher adoption: environment variables not restored

`tools/qa/Invoke-IsolatedGodotQA.ps1:121-126` overwrites **process-scoped** PowerShell environment values: `APPDATA`, `LOCALAPPDATA`, `FISHING_QA_RUN_ID`, `FISHING_QA_SANDBOX`, `FISHING_QA_USER_DIR`, `FISHING_QA_PERSISTENCE_PATHS`.

In PowerShell, a `.ps1` script run with `&`/`./` shares its PowerShell process's environment. The `finally` at lines 162-178 restores `project.godot` but **does not restore these environment variables**. A later command or application launched from that same PowerShell terminal can inherit the QA sandbox AppData path. This is a concrete environment-lifecycle defect revealed by code inspection, not an observed leaked save in Godot.

**Minimal correction:** Snapshot these six variables before any mutation and restore their exact prior values in `finally`, on successful tests, failed tests, exceptions, and interrupted-but-handled runs. Use process environment APIs that distinguish missing variables from present values. Do not restore them until Godot has exited, and retain the existing journal/lock protection. Avoid scope creep. Add one integration check that calls the script from a persistent PowerShell session, captures all six variables before and after a passing recovery run and a rejected run, and proves equality (including unset variables).

A workaround is to launch the wrapper in a **new child PowerShell process**, then exit that process after the test; the parent shell will not inherit child environment changes. That is not a substitute for making the documented launcher safe when run directly.

## R05 — minor validation tightening, same correction pass

`Invoke-IsolatedGodotQA.ps1:150-152` casts `result.failed` and `result.orphans` to integers without asserting that both JSON fields exist and are integer-valued. Missing fields could become zero and be accepted when `passed == total`. Explicitly require all five keys (`suite`, `passed`, `total`, `failed`, `orphans`) with correct types before trusting their values. Keep the existing check that failed==0 and orphans==0. Add one negative probe for a missing `orphans` key with a zero Godot exit code; the launcher must reject it.

## Separate suite failures — track, don't silently classify as pre-existing

| Suite | Reported result | Specific failure scope |
|---|---:|---|
| `fishing_save_recovery_runner` | 23/23 passed | isolation/recovery baseline |
| `playable_content_delivery_qa` | 1453/1453 passed | migrated fixture |
| `fishing_camera_hud_stability_qa` | 79/79 passed | migrated fixture |
| `session_composition_separation_qa` | 102/102 assertions, launcher rejects | five Weather Sense errors in its nested session QA |
| `session_contract_runner` | 24024/24029 | five Weather Sense expectations |
| `empty_lure_retrieval_qa` | 285/286 | retrieval resistance against action/current contribution |
| `universal_input_qa` | 143/148 | desktop held-click and mobile touch/menu interactions |
| `canonical_portrait_surface_qa` | 466/467 | inventory/menu canvas sizing |

These are **observed errors**, not necessarily caused by isolation. The handoff does not contain matched before/after runs on the unmodified FRESH6 baseline in the same isolated environment. Do not claim they were pre-existing or regression-free until separately compared. Do not weaken assertions or modify gameplay as part of Repair 01.

## Acceptance gate after micro-correction

1. Original FRESH6 files remain byte-identical; only the QA/tooling disposable copy is changed.
2. All original R01/R02/R03 positive and negative safeguards remain in place.
3. `APPDATA`, `LOCALAPPDATA` and every `FISHING_QA_*` environment variable is exactly restored after success and failure.
4. Missing or malformed structured fields are rejected.
5. Recovery runner still reports 23/23, zero failures/orphans, with manifest and actual sandbox paths.
6. Report all other suite failures without changing their test assertions or claiming them fixed.
7. Provide only the updated launcher and any necessary result validation test/documentation, with a handoff ZIP and rollback instructions; do not repackage or modify unrelated files.

After these corrections, **Foundation Repair 01 can be accepted for isolated QA in marked disposable project copies**. It does not make direct F5 runs safe or fix the confirmed catch journal, interrupted JSON save, or multi-store transaction defects. Next feature repair should be catch journal recovery using the safe launcher.
