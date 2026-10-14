# Environmental Integration v5 — Lake & River fishing-loop handoff

**Prerequisite:** Environmental Integration v1–v3 installed, v3 repair applied, v4 Lake/River QA green (reported by user: **133 passed, 0 failed**). Requires Godot 4.7.2 or compatible project version.

## Scope

This is a **new QA harness only**; it does **not** replace or edit any gameplay, VFX, camera, scene, or save implementation. It loads the real Lake 2 and River 2 packed scenes; enters fishing through the real K shoreline event; instantiates the real Caster bait using authored rod/lure/zone; forces a controlled water contact for deterministic engine QA; checks a genuine nonterminal bite miss, location-specific fish selection, confirmed fight, catch landing, durable repository transaction, species/lure/spot attribution, duplicate-catch protection and post-exit cleanup.

The test **does not** simulate human K timing for the full power/curve cast animation, fish fights over several resistance rounds, physically reeled lure travel, or a screenshot/visual audit. Those remain hands-on playtest gates. The controlled landed bait is the same setup pattern used by the project's existing `runtime_lifecycle_qa.gd`; the runtime ownership, encounter, and catch functions are **real production methods**, not mocks.

The QA creates a **unique isolated** `user://` data directory before loading gameplay, so successful test catches are saved only under that test directory and cannot touch the player's normal save. It never changes the Inspector Rain Preview setting on disk. The new script is additive and preserves all existing patches.

## Run on Windows PowerShell

Open the Godot editor. Navigate to the FishingGame project folder in PowerShell and paste **only the code block**, not the `PS ...>` prompt or the test output.

```powershell
$godot = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like "Godot*" -and $_.Path } |
    Select-Object -First 1 -ExpandProperty Path
if (-not $godot) { throw "Open Godot first." }
$console = $godot -replace '\.exe$', '_console.exe'
if (Test-Path $console) { $godot = $console }
& $godot --headless --path . --script res://scripts/qa/environment_integration_v5_fishing_loop_qa.gd
```

Treat any `FAILED` or Godot parser error as a real stop. Send the full failure messages, not just the count.

## Manual acceptance — actual fishing feel

For **both** Lake 2 and River 2, do the following from a normal new or existing save, separately from the automated test.

1. Enter the shoreline via K; use K across Prep → power → curve → throw, then visually confirm the actual airborne cast and water contact.
2. Check the correct species silhouettes/shadows for that location; allow one bite to expire and then hook another at the intended window.
3. Fight using steering, tension and reel/pull, and complete a genuine landing. Confirm species name and spot in catch records, physical inventory increase, and any legitimate reward notification.
4. Repeat while raining and while clear; observe rain/weather transitions without losing the hook timing, camera follow or VFX.
5. Exit fishing and travel between Lake and River. The previous fish population/current must not leak into the next location. If possible, save/reload after a catch and verify the same inventory and record.

**Known polish backlog:** current tint/fade across deep water, subtle per-raindrop angle variance. Leave rain, wind, currents, and camera visuals untouched for this backend/QA phase.
