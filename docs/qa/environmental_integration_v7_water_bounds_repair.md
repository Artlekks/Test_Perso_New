# Environmental Integration v7 — water-contact and camera-setup QA repair

Use after v7 and the previous v7 fade repair. This **only** replaces `scripts/qa/environment_integration_v7_live_weather_qa.gd`. No production camera/VFX/fishing data, Godot scene, or saved Inspector setting is altered.

## Finding from your second run

180/182 checks passed, with two HUD overlap events at roughly `(466, 406)` on Lake 2 and River 2. The original v7 harness skipped the scene's real 0.7 s fishing-view camera tween and then selected an impact by intersecting a screen ray with an infinite water plane. Screen-visible **does not mean water-valid**; these two assumptions could produce a controlled contact with invalid camera/shoreline geometry.

## Changes

- Wait for the actual 0.7 s fishing-view camera transition before beginning AIM, rather than manually advancing the gameplay state while the camera is still tweening.
- Select the controlled landing from the location's authored `FishSwimBounds`, accepting only points on the water side of `FishingShoreBoundary`, inside the actual camera safe region, and clear of live fishing HUD rectangles. No fishing/camera safety check is disabled.
- Retain the HUD safety assertion with additional projected-pixel and lure-world-position diagnostics in case this exposed a real camera regression rather than only an invalid test fixture.
- Preserve the rest of v7, including automatic-weather, rain fade, fish fight/catch, durability, and location continuity checks. Save isolation remains intact.

This fix has passed package integrity and source inspection only. It has not been run under Godot 4.7.2 in this environment. If the HUD violation persists using a real in-bounds water point, it should be treated as a camera regression for separate investigation rather than bypassed.

## Windows PowerShell (run from the project directory with Godot editor open)

```powershell
$godot = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like "Godot*" -and $_.Path } |
    Select-Object -First 1 -ExpandProperty Path
if (-not $godot) { throw "Open Godot first." }
$console = $godot -replace '\.exe$', '_console.exe'
if (Test-Path $console) { $godot = $console }
& $godot --headless --path . --script res://scripts/qa/environment_integration_v7_live_weather_qa.gd
```
