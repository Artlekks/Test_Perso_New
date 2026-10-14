# Environmental Integration v3 — lifecycle continuity

Layer this patch after v1 and v2, including the v2 QA correction.

## Focus
- Fix a startup race in Auto rain: if the scene mounts before the deferred
  GameWeather service exists, the rain no longer mistakes a missing provider
  or the fishing service's provisional Calm default for an actual Clear
  condition. It waits for authoritative weather, then initializes directly
  at the correct intensity (without an unnecessary fade-in).
- No changes to rain/splash aesthetics, particles, camera, color, wind,
  currents, fishing physics, condition probabilities or weather transitions.
- The new integrated QA uses disposable user:// storage. It runs a real beach
  scene, switches fishing/exploration, crosses calm/rain/tempest, saves and
  reloads GameClock, swaps to an authored ocean scene, and checks both locations
  agree with the authoritative clock, wind, weather and gameplay tags.
- Direct scene swapping in QA is deliberate: it exercises environmental scene
  lifecycle separately from progression/travel unlocks; the existing
  world_location_access_qa.gd covers the complete route/access logic.

## Test on Windows (PowerShell)
With the Godot editor running, paste only this command block, from the project root:

```powershell
$godot = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Godot*" -and $_.Path } | Select-Object -First 1 -ExpandProperty Path
if (-not $godot) { throw "Open Godot first." }
$console = $godot -replace '\.exe$', '_console.exe'
if (Test-Path $console) { $godot = $console }
& $godot --headless --path . --script res://scripts/qa/environment_integration_v3_qa.gd
```

Do not paste terminal output into PowerShell as commands.
This QA uses a unique isolated save folder. Existing user:// clock and fishing
saves are not read or changed. If the real-scene test fails, keep its log;
we should correct the specific assertion or bug before moving on.

## Manual visual verification
Run a real rainy scene, switch fishing mode, then return to exploration.
Enter another location while rainy. Rain should start at settled intensity
and continue through the scene, without duplicate VFX or camera changes.
No new visual polish work is included in this pass.
