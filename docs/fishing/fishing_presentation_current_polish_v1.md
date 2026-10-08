# Fishing Fight Presentation & Current Polish v1

## Screen ceiling

`Fishing/ScreenWaterBounds` runs at process priority 100, after the existing camera yaw and bait physics. It operates only in `IN_WATER` or hooked `FIGHT`, and only with a physically waterborne active bait. Visibility and viewport inclusion do not gate it.

The effective normalized top boundary is:

```text
max(top_safe_ratio, FishingInfoView resting bar bottom / viewport height + info_margin_ratio)
```

Defaults: `top_safe_ratio = 0.18`, `info_margin_ratio = 0.05`. At 640x480 the authored bar bottom measures 61px; the effective ceiling is 86.4px. The resting layout is measured even when the notice is hidden, sliding or displayed in exploration, so showing a notice does not suddenly change the allowed water area.

An offending point is projected with the active `Camera3D`, then the corrected screen pixel is intersected with the bait's existing depth plane. This changes X/Z as needed, preserving world Y and projected screen X. There is no fixed world-Y clamp, X clamp, camera transform change or new camera owner. Behind-camera points are left to the existing yaw tracker rather than resolved through a reversed camera ray.

Hooked shadows and surface ripples update at priority 105; the existing fishing line already updates at 110. They therefore follow the corrected physical point in the same rendered frame.

The lower-right depth HUD starts at y=354px. A broad lower clamp was investigated and removed: it can prevent the physical bait reaching the existing return radius, particularly at deep fight depths. The final production constraint is top-only. Existing horizontal tracking is preserved; lower HUD/corner presentation still requires normal-play review. No landing exemptions, return thresholds, fish depth changes or camera retuning were introduced to conceal that conflict.

Tunables are exported on the runtime `ScreenWaterBounds` component; its script holds the persistent defaults. Current presentation controls are exported on `FishingCurrentSurfaceView`, also created by the existing fishing controller.

## Current

Physical drift already existed in `Bait._update_current_drift`. This pass preserves the authored force strength and adds a common angular/magnitude smoothing function on `FishingCurrentService`. Bait and streaks sample that service using its canonical time, authored spot direction/speed, local current fields, gust and tide modifiers. The old visual-only clock has been removed.

`direction_response = 2.0` uses exponential response `1 - exp(-response * dt)`; heading uses `lerp_angle`, so an authored reversal turns gradually rather than flipping through a zero vector. Each moving consumer retains its previous sampled velocity; local fields can legitimately differ at different world positions.

Drift is added after existing player steering, as velocity times delta, constrained through the existing swim bounds. It applies to `SINKING`/`IN_WATER`, including hooked fights (the physical bait retains a waterborne state). It does not apply while airborne/idle or simulation-frozen during landing. Authored strength and global fish difficulty are unchanged.

The old short travel/reset cycle is replaced with persistent UV travel along the canonical current. Bounds wrapping fades over 6% of the field edge. Fifteen static subdivided plane meshes share a shader; wave displacement uses the GPU, without rebuilding meshes per frame.

| Control | Default |
| --- | --- |
| Flow speed at reference strength | 0.18 world units/sec |
| Wave amplitude | 0.035 world units |
| Wavelength | 0.4 world units |
| Phase speed | 1.2 radians/sec |
| Current direction/magnitude response | 2.0 /sec |

Flow speed scales by the sampled/reference current ratio, capped to the existing 0.25–2.4 visual range. Prediction markers continue using the existing current service; their clock is now canonical too.

## Landing shadow

`Encounter.begin_catch_landing()` accepts the authoritative `HOOKED -> LANDING` transition. It now calls `FishShadowActor.begin_catch_landing()` to hide and detach the underwater actor immediately, then clears encounter/presence ownership through the existing `_end_active_fight_shadow(false)` path. This precedes the shoreline splash in `Fishing._begin_catch_landing()`.

The existing expiry handles resource cleanup only; visibility does not wait on a delay. Normal hooked tracking stays visible. Escape/missed-catch dive/fade paths remain, and a subsequent catch creates a fresh visible shadow.

## Verification

Run from the current project root, with the configured Godot executable:

```powershell
& 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe' --headless --path . --quit-after 1800 --script res://scripts/qa/fishing_presentation_current_polish_qa.gd
& 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe' --headless --path . --quit-after 1800 --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions
git diff --check
```

Both runners create disposable isolated userdata before gameplay bootstrap. Actual runs also passed `--log-file` pointing to the task artifact directory.

| Suite | Final result |
| --- | --- |
| Focused presentation/current QA | 164/164 |
| Fight-camera QA | 120/120 |
| Full fishing regression | 22950/22950 |
| Fishing Fight | 24/24 |
| Fishing Presentation | 10/10 |
| Fishing System Stability | 27/27 |
| Weather Sense / Tide Sense | 22/22 / 31/31 |
| Current Reader / Drift Angler | 17/17 / 29/29 |
| Weather Watcher / Tide Reader | 31/31 / 39/39 |
| Fresh Save Rehearsal | 55/55 |

Focused QA covers projection at 320x240, 640x480 and 1280x960 with yaw -55/0/+55; hidden target equivalence; actual runtime phase gates; stable resting HUD measurement; real steering plus drift; strength scaling; gradual reversals; no airborne/frozen drift; continuous streak movement and faded wrap; mesh reuse; shadow landing/expiry/escape/missed/consecutive lifecycle; and real slow-reel landing reachability at 0.1/1.0/2.5m depths.

Existing startup warnings remain visible: the known two H12 balance alerts (22/24 economy guardrails) and the expected Triple Triad defensive QA warning. No economy/progression values were changed.

## Rendered evidence and limitations

A temporary runner in the external task artifact directory captured controlled rendered samples of the production scene/HUD and a close-up of the production current shader. Top-left/right samples projected to y=86.4px. These are scripted fixtures, not a normal-play approval. The shader visibly produces wavy streaks.

The Forward+ and Compatibility fixture runs produced engine `_save_to_cache: f.is_null()` write errors, although images were produced and there were no script/shader compilation failures. A temporary short-path junction did not eliminate the errors; their filesystem cause is unresolved. Project rendering settings were not changed or errors suppressed. Do not describe these rendered runs as error-free. Headless QA passed separately.

Visual review in normal Godot play remains required:

1. Cast normally, steer both edges in `IN_WATER`, hook a fish, and check the top info/thrash notice with shallow/deep bait and camera yaw.
2. Confirm current speed, waviness, opacity and gradual turning at an unlocked Current Reader location; compare bait drift with A/D steering.
3. Inspect lower HUD corners during retrieve, landing and escape, especially deep bait. The new constraint protects the top notice only.
4. Land consecutive fish and confirm the shadow disappears before the splash, underwater fight shadows remain, and escape/missed fish retain their dive/fade.
5. Verify frame smoothness when the top constraint is active near swim/shore boundaries.

## Changed project files

- `scripts/bait_V2.gd`
- `scripts/encounter.gd`
- `scripts/fish_shadow_actor.gd`
- `scripts/fishing.gd`
- `scripts/fishing_current_service.gd`
- `scripts/fishing_current_surface_view.gd`
- `scripts/fishing_info_view.gd`
- `scripts/ripple_view.gd`
- `scripts/fishing_screen_water_bounds.gd` and its new `.uid`
- `scripts/qa/fishing_presentation_current_polish_qa.gd` and its new `.uid`
- This report.
