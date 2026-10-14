# Environmental Integration v7 — QA Repair

Prerequisites: Environmental Integration v1–v7 installed in project. **Test-only change:** one QA script replaced. No production VFX, gameplay, camera, fish, world scenes, textures, settings, or saved data are changed.

The first v7 engine run reported `176 passed, 2 failed`, both for the Tempest → Calm live fade check, plus two independent `FISHING HUD OVERLAP VIOLATION` engine messages.

## Changes

1. **Fade synchronization:** After the weather provider and rain target both read Clear, observe subsequent actual scene process frames for up to 800ms before judging whether the visible rain level has begun to decline. This avoids a timing race where the clock-condition change and the VFX presentation update occur at opposite ends of the previous fixed 0.6s wait. The test still fails if `_rain_level` does not decrease; no render value or production fade logic is overridden. If the test fails, the assertion now reports the level before and after, target, pause state and whether the rain node can process.
2. **Safe, controlled bait contact:** During the QA-only shortcut for physical water impact, project a desired pixel inside the actual fishing camera's safe HUD-free region back onto the authored water-height plane. The previous fixture teleported bait to the `WaterSurface` node's *origin*, which can be outside the acceptable HUD composition even if the water volume itself is broad. The production camera invariant remains active, and the QA now explicitly checks that this scenario does not increase HUD overlap violations.

The physical cast arc, animation completion, and bite-ready cue remain controlled, as documented for v7. This is still not a human-controlled gameplay/camera certification.

## Installation

Extract `Environmental_Integration_v7_QA_repair.zip` to your project root (the folder with `project.godot`). Replace:

- `scripts/qa/environment_integration_v7_live_weather_qa.gd`

The README is added in `docs/qa`.

## PowerShell — launch QA with the current open Godot editor

```powershell
$godot = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like "Godot*" -and $_.Path } |
    Select-Object -First 1 -ExpandProperty Path
if (-not $godot) { throw "Open Godot first." }
$console = $godot -replace '\.exe$', '_console.exe'
if (Test-Path $console) { $godot = $console }
& $godot --headless --path . --script res://scripts/qa/environment_integration_v7_live_weather_qa.gd
```

This repair was statically reviewed, but the Godot executable is not available in this environment. Your Godot 4.7.2 runtime result is required to confirm it.
