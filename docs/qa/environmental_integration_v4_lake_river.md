# Environmental Integration v4 — Lake/River gameplay handoff QA

Applies **after v1, v2, v3 and the v3 QA repair**. v3 must pass (65 passed, 0 failed).

**Why this pass:** v3 established beach/ocean world weather continuity. This checks the next two actual authored gameplay locations: `lyp_lake_outpost` (Lake 2) and `river_fishing_outpost` (River 2), then returns to Lake 2 to look for stale River state. Uses each location's existing real packed scene and fishing zone, not a mock population.

The harness validates: real scene composition and location binding; World-owned rain/wind/current VFX without modifying them; rain/scheduled weather and shared clock/wind state; authored fish populations; ecology/weather/spot/current/swim-bound handoff on fishing entry; and teardown on fishing exit. Actual K-input shoreline entry and synchronized local current/ecology sampling are exercised. Direct scene swaps deliberately bypass travel unlocks because `world_location_access_qa.gd` already covers item gates and full travel routing. No fish, zenny, inventory, rod, or tackle is added by this test.

**Files installed:** `scripts/qa/environment_integration_v4_lake_river_qa.gd` (new) and this documentation. **No production files are replaced**—no changes to camera, rain visuals, splash values, currents, wind, fish odds, world services or saved scenes.

## Run on Windows PowerShell

Open Godot, navigate to your project root in PowerShell, then paste only this code block:

```powershell
$godot = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like "Godot*" -and $_.Path } |
    Select-Object -First 1 -ExpandProperty Path
if (-not $godot) { throw "Open Godot first." }
$console = $godot -replace '\.exe$', '_console.exe'
if (Test-Path $console) { $godot = $console }
& $godot --headless --path . --script res://scripts/qa/environment_integration_v4_lake_river_qa.gd
```

The test creates a unique **isolated** `user://` folder before loading scenes. Its Rain Mode override is limited to test instances; it does not change your saved Inspector Preview mode.

**Status:** static inspection and ZIP integrity only. This new test has not yet been run in your Godot 4.7.2 engine. Report the exact final pass/fail line and any failure details, and we will address the specific break before changing gameplay.

Once this is green, the next useful step is interactive Lake/River playtesting: shoreline entry, casting, species selection, bite/fight and catch/reward flow. The environmental QA is not a replacement for the visual and input playtest.
