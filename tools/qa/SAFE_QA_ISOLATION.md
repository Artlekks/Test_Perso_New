# Safe QA isolation — Windows installation and rollback

## Install and run

1. Copy frozen FRESH6 to a separate disposable directory. Apply the package's `scripts/qa` and `tools/qa` files at their original relative paths **in the copy only**. Do not run QA against frozen FRESH6.
2. In the copy root create `.qa_disposable_copy.json` with `{"baseline":"C:\\absolute\\path\\to\\FishingGame_Audit_FRESH6"}`. The marker must never be placed in the frozen source.
3. With PowerShell 7 or Windows PowerShell 5.1, run from that copy:

   ```powershell
   $godot = 'C:\path\to\Godot_v4.7.2-stable_win64.exe'
   .\tools\qa\Invoke-IsolatedGodotQA.ps1 -GodotExe $godot -ValidateOnly
   .\tools\qa\Invoke-IsolatedGodotQA.ps1 -GodotExe $godot -Import
   .\tools\qa\Invoke-IsolatedGodotQA.ps1 -GodotExe $godot
   .\tools\qa\Invoke-IsolatedGodotQA.ps1 -GodotExe $godot -Runner 'res://scripts/qa/playable_content_delivery_qa.gd'
   ```

`-ValidateOnly` checks paths and writability but does not edit `project.godot` or start Godot. Actual runs acquire an exclusive same-copy lock, save the exact original project bytes in `project.godot.qa.original.json`, atomically set a fresh `FishingQA_<GUID>` custom user directory, redirect `APPDATA` and `LOCALAPPDATA`, and start Godot. The launcher restores and hash-checks the original project bytes after Godot exits, including failed suites. A simultaneous invocation is rejected before Godot starts.

After an interrupted launcher, a remaining journal blocks new runs. Wait until Godot has exited, then run `Invoke-IsolatedGodotQA.ps1 -GodotExe $godot -Recover`. Recovery holds the same lock, refuses while any Godot process is running, verifies the journal hash, and restores the original bytes. Do not delete the journal or launch directly while recovery is pending.

The launcher accepts `-PersistencePaths @('user://my_suite/save.json')` for additional configured paths. Absolute paths outside the generated user directory are rejected before Godot starts. Every runner must call `qa_save_isolation.gd` from `_initialize()`, verify the root clock before constructing a fixture, emit exactly one `QA_SUITE_RESULT` containing suite identity, actual passed/total/failed counts, and orphan count, then print `QA_PROCESS_FINALIZED` from its `SceneTree._finalize()` callback. The launcher requires a positive total, passed + failed = total, failed = 0, passed = total, zero orphans, matching suite identity, one later clean-shutdown marker, Godot exit 0, and no unexpected Godot runtime error. A Windows self-kill can report exit 0, so the shutdown marker is required even when the structured result looks successful. It retains stderr and labels expected negative-control write warnings separately.

All seven `SessionTestFixture` entry points are migrated: `canonical_portrait_surface_qa.gd`, `empty_lure_retrieval_qa.gd`, `fishing_camera_hud_stability_qa.gd`, `playable_content_delivery_qa.gd`, `session_composition_separation_qa.gd`, `universal_input_qa.gd`, and `session_contract_runner.gd`. Their early validation requires this launcher. QA capture and manually supplied input paths now stay under the isolated `user://` directory. The recovery runner also uses the same contract. Logs and the manifest are under `qa_sandboxes/<run id>`.

## Scope and rollback

This protects runs launched by the wrapper from the marked disposable copy. It does not certify F5 or direct `--script` launches, arbitrary paths supplied later by unrelated code, or existing player saves.

For rollback, finish or recover any pending run first. Restore the ten changed QA scripts from the frozen FRESH6 source and remove the new `scripts/qa/qa_save_isolation.gd`, `tools/qa/QaIsolation.psm1`, `tools/qa/Invoke-IsolatedGodotQA.ps1`, and this guide from the development copy. The frozen source itself needs no rollback. The corrected launcher restores `project.godot` after each normal run; verify it matches the pre-run hash before discarding the copy.
