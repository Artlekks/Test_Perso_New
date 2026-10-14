# Environmental Integration v7 — live weather during fishing

Prerequisite: Environmental Integration v1–v6 installed; user reported v6 QA passed. This package is **additive QA only**: no production scripts, scenes, textures, camera, wind, currents or approved rain settings are modified.

## Purpose

v4–v6 verified Lake/River handoff, complete catches and K/I input gates. v7 fills the remaining *dynamic* integration gap: the weather scheduler changes **while a player is actively fishing**, not just between locations.

For each of the authored **Lake 2** and **River 2** scenes, v7 checks:

1. Load under scheduled **Calm** weather and confirm world weather/ecology/rain agree, with Auto preview applied **only at runtime**.
2. Enter fishing via a real physical **K** event; verify AIM and local current binding.
3. Transition **Calm → Rain during AIM**, confirming the same weather reaches GameWeather, the fishing environment, world snapshots and rain presentation; inspect the rain fade, which must be gradual rather than instant.
4. Cast using actual K action paths through Prep Throw, Charge, Curve and Throw; only sprite completion and the physics water-contact callback are controlled to avoid timing uncertainty.
5. Transition **Rain → Tempest during IN_WATER**, confirming the active bait, fishing phase, water current and fish inventory remain consistent; check a gradual storm-emphasis blend.
6. Hook a local fish through the real K input path (with a controlled bite-ready cue), then transition **Tempest → Calm during FIGHT**. Verify the fight and hooked specimen survive and the visible rain fades down gradually, not abruptly.
7. Complete the real landing/catch repository path; verify precisely one durable catch, assigned to the correct fishing spot. Check fishing exit clears the old current/ecology bindings and does not discard the catch.
8. Change the weather again during exploration. Unload the location, then repeat in the other location without old-world state leakage.

### Limits

This is a **headless automated integration** test, not a visual certification. It does not simulate human timing, rendered particle appearance, long fights, physical bait arcs or manual gameplay feel. It makes deliberate controlled callbacks for bait landing, animation completion and bite readiness, just as v5/v6 did. It does **not** make weather signals/polling instantaneous: after clock changes it waits >0.5 seconds for normal rain polling and normal gameplay notifications.

The environment's actual visual fade durations remain configurable. The test expects positive fade times and an initially clear scene. If you deliberately configured a zero-second transition in the Inspector, that specific visual assertion is not applicable; tell me rather than altering the game's approved settings to force a pass.

### Safety

The QA selects a unique temporary `user://` directory before the project autoloads are used, and aborts if it cannot isolate storage. It never changes your project files or the rain scene's Inspector values. Rain Preview is forced to Auto only in instantiated QA nodes. It prints test failures but continues when it can, exiting with a nonzero process code on failure.

## Installation

Unzip `Environmental_Integration_v7_Live_Weather.zip` into the project root (folder containing `project.godot`). It adds:

- `scripts/qa/environment_integration_v7_live_weather_qa.gd`
- `docs/qa/environmental_integration_v7_live_weather.md`

It does not replace `fishing.gd` or any existing scene or VFX script.

## Windows PowerShell (Godot already open)

Open PowerShell in the project root. Paste only this code, not the terminal prompt or subsequent test output:

```powershell
$godot = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like "Godot*" -and $_.Path } |
    Select-Object -First 1 -ExpandProperty Path
if (-not $godot) { throw "Open Godot first." }
$console = $godot -replace '\.exe$', '_console.exe'
if (Test-Path $console) { $godot = $console }
& $godot --headless --path . --script res://scripts/qa/environment_integration_v7_live_weather_qa.gd
```

Expected console footer: `Environmental Integration v7 Live Weather QA: X passed, 0 failed` if green. **No engine pass count is asserted in advance.** Any `FAILED` or parse error needs investigation. The QA has been statically reviewed, but has **not** been executed under Godot 4.7.2 in this environment.

## Hands-on acceptance still outstanding

1. Lake 2 and River 2: play an actual cast, bite and 20–30-second fight with weather transitions active. Confirm steering, rod animation, fight camera and catch feedback remain natural.
2. Watch rain fade while a lure is in water, confirm splashes continue over both water and shore, and watch a storm become clear while the fish remains hooked.
3. Switch Lake ↔ River during gameplay and check records, inventory and environment. If the visual weather doesn't reflect gameplay, report which phase and screenshot.

Deferred optional visual polish: deep-water current tint and slight irregularity in individual rain-drop angles. No new effects are required for this phase.
