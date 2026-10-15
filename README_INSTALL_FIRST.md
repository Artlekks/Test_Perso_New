# FishingGame — Foundation Repair 01: consolidated QA-only installation

This ZIP consolidates the R01–R03 corrected handoff with the R04–R05 launcher-only correction. It contains only the project-relative QA and tooling files required for installation plus this note. It contains NO modified gameplay code, saves, scenes, or assets.

## Scope and safety

**Install only into a disposable copy of FRESH6**, not the frozen audit baseline or your active gameplay project. This workflow protects runs launched through the special launcher. It does not make raw Godot F5 or manually invoked QA scripts safe.

1. Make a complete, separate copy of FRESH6 and extract this ZIP into that copy's root, preserving all paths. `project.godot` must remain the copied original file.
2. In the disposable project root, create `.qa_disposable_copy.json` containing a JSON object with `baseline` set to the absolute path of your separate frozen FRESH6 project, for example: `{"baseline":"C:\\Users\\...\\FishingGame_Audit_FRESH6"}`. Do NOT create this marker in your baseline.
3. Read `tools/qa/SAFE_QA_ISOLATION.md`. In PowerShell, from the disposable project directory:

```powershell
$godot = 'C:\path\to\Godot_v4.7.2-stable_win64.exe'
.\tools\qa\Invoke-IsolatedGodotQA.ps1 -GodotExe $godot -ValidateOnly
.\tools\qa\Invoke-IsolatedGodotQA.ps1 -GodotExe $godot -Import
.\tools\qa\Invoke-IsolatedGodotQA.ps1 -GodotExe $godot
```

Always inspect test output. A successful launcher exit must include `QA_RESULT_PASS` for a suite, not just a Godot exit code of 0. Import is handled separately.

If a run leaves `project.godot.qa.original.json`, DO NOT delete it. When no Godot process is running, use `-Recover` per the guide.

## Verification status

The supplied R04/R05 handoff logs report: recovery QA 23/23, 0 failed, 0 orphans; before/after environment variables identical after both passing and failing runs; three malformed/missing structured results rejected. Corrected-launcher reports also contain positive/negative tests for source config restoration, concurrent-run prevention, and save-root isolation. This consolidated ZIP copies code from those reviewed handoffs; no additional Godot execution was performed for this consolidation.

Remaining unrelated failures are NOT resolved: Weather Sense (5), Universal Input (5), Empty Lure Retrieval (1), Canonical Portrait (1). Previous reports do not prove whether they predate QA migration. Foundation Repair 02 (catch journal durability) remains outstanding.

## Rollback

Only after any active QA run is finished/recovered, replace the ten modified scripts under `scripts/qa/` from frozen FRESH6, then remove the four new files (`scripts/qa/qa_save_isolation.gd`, `tools/qa/QaIsolation.psm1`, `tools/qa/Invoke-IsolatedGodotQA.ps1`, `tools/qa/SAFE_QA_ISOLATION.md`). You can instead delete the entire disposable copy.

## Package origin

Project files here are copied byte-for-byte from `FishingGame_Safe_QA_Isolation_Corrected_Handoff.zip`, except `tools/qa/Invoke-IsolatedGodotQA.ps1`, which is copied byte-for-byte from the R04/R05 micro-correction ZIP.
