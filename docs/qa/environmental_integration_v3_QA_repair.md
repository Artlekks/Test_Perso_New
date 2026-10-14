# Environmental Integration v3 — QA repair

Apply **after** Environmental Integration v1, v2 and v3. This is NOT a new integration feature.

## What was wrong

1. `fishing_rain_world_vfx.gd` called `get_tree()` from a detached test scene; Godot reports `data.tree is null`. It now checks `is_inside_tree()` before reading the world provider. It still reads `GameWeather` for normal attached scenes.
2. v3 test inherited `weather_mode` from the artist's saved `FishingRainVFX.tscn` (which may be Rain or Storm Preview), contrary to v2 QA's approach. This prevents a test of authoritative weather transitions and caused the remaining 4 assertions. The repaired fixture explicitly uses Auto; a SceneTree `node_added` callback sets dynamically mounted rain instances to Auto before their `_ready()` logic initializes. Only the QA process is affected. The saved `.tscn` and all its Inspector settings remain unchanged.

## Files replaced

- `scripts/environment_fx/fishing_rain_world_vfx.gd`
- `scripts/qa/environment_integration_v3_qa.gd`

## QA on Windows (PowerShell)

With Godot open, from your project root, paste ONLY the code below. Do not paste its output back into PowerShell.

```powershell
$godot = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like "Godot*" -and $_.Path } |
    Select-Object -First 1 -ExpandProperty Path
if (-not $godot) { throw "Open the Godot editor first." }
$console = $godot -replace '\.exe$', '_console.exe'
if (Test-Path $console) { $godot = $console }
& $godot --headless --path . --script res://scripts/qa/environment_integration_v3_qa.gd
```

Expected based on the patch: the four previous failures and the two detached-node warnings should no longer occur. This patch has NOT been executed against Godot 4.7.2 in this environment; report any residual failures exactly as printed.

**Important for real gameplay**: `FishingRainVFX.tscn` must have its Rain Mode set to **Auto** to follow the scheduled weather. Rain / Storm Preview modes intentionally override global weather; this patch does not silently change your saved mode because preview remains useful for visual work. The QA forces Auto only in its test instances.

**Scope**: no changes to rain art, rate, splash values, camera, wind, currents, fishing gameplay, saves, or environmental scheduler.
