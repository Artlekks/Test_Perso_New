# Environmental Integration v6 — Lake/River cast-input and bite recovery

**Prerequisite:** Environmental Integration v1–v5 installed, with v5 Fishing Loop QA passing (user reported **96 passed, 0 failed**). Tested against the FRESH5 code baseline, with v1–v5 update files applied in order. Godot 4.7.2 is the user's runtime.

## Contents and purpose

- `scripts/fishing.gd` — original filename, two **minimal** cast-input-gate re-arm guards after entrance `Prep_Fishing` and backwards `Prep_Throw` cancel animations. If the previous K is already released when returning to AIM, the next *fresh* press is accepted. A held K remains blocked. This avoids a missed first cast after pressing K to enter fishing and releasing K before the entrance animation finishes. No camera, animation, mechanic, reward, weather or VFX tuning was changed.
- `scripts/qa/environment_integration_v6_player_input_qa.gd` — new isolated-save, headless integration test for Lake 2 and River 2.

v6 checks real location entry by dispatched physical K, cast button stage gating (including rejecting held K and accepting a deliberately buffered second K), controlled water contact, early hook miss without inventory gain, I quick-cancel recovery, successful K-to-hook on the next cast, continuous held-reel and A/D steering state, production landing and durable catch, post-exit ecology/current teardown, and cross-location inventory continuity.

**Important test boundary:** v6 uses real `Fishing._unhandled_input()` gameplay action events and `Input.action_press/release` for fishing controls, but it intentionally invokes *animation-finished callbacks* and *bait landed* with controlled timing to eliminate rendering/physics nondeterminism. It is **not** an automated test of physical animation speed, the camera's appearance, splash visuals, frame-perfect human reaction or mouse/gamepad hardware routing. Those still need hands-on checks.

Save isolation: the test selects a unique custom `user://` folder before loading gameplay, and aborts rather than running with normal user data if isolation cannot be established. It does not alter your saved Inspector settings. Rain Preview is set to Auto only for the loaded test scene, not on disk.

## Install

Unzip `Environmental_Integration_v6_Player_Input_FRESH5.zip` at the project root (the folder containing `project.godot`). Let Windows replace `scripts/fishing.gd`, and add the new QA script/documentation. **Do not delete other files.** Make a backup or commit first, as usual for production script replacement.

## Run from Windows PowerShell

Open the Godot editor and make sure PowerShell's current folder is the project root. Paste only the following PowerShell commands, without any `PS ...>` prompts, and **do not paste Godot error output back into PowerShell**.

```powershell
$godot = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like "Godot*" -and $_.Path } |
    Select-Object -First 1 -ExpandProperty Path
if (-not $godot) { throw "Open Godot first." }
$console = $godot -replace '\.exe$', '_console.exe'
if (Test-Path $console) { $godot = $console }
& $godot --headless --path . --script res://scripts/qa/environment_integration_v6_player_input_qa.gd
```

The script will print `Environmental Integration v6 Player Input QA: X passed, Y failed`. **No specific pass count is promised; QA has not been run in Godot in the author's environment.** Any `FAILED` lines or parse errors are blockers.

## Manual acceptance (still required)

1. **Lake 2:** At shoreline tap **K**, release it *before* the entrance animation ends. Once AIM is ready, tap K again. The very first fresh K must enter PREP_THROW. Finish a real manual cast with K -> power -> curve -> K; compare preview to physical landing.
2. Cast again but press the second K *during* Prep_Throw, then release; it must buffer and enter CURVE once the animation completes. Holding one K should never skip two stages.
3. Let a bite expire, try an early hook, and verify neither creates a catch. While an unhooked bait waits in the water, press **I** to abandon and return to AIM. Another cast must be possible immediately.
4. Hook a valid fish with K at the cue; test K reel, A/D counter-steering and S pulls. Actually fight and land. Catch count and spot records must match.
5. **River 2:** Repeat steps 1–4. Check that fish ecology and current direction are local to the River, and rain/weather UI and VFX still match the shared clock/weather state.
6. Exit fishing, travel back to Lake, and check previous catch inventory and records. Observe both clear and rainy weather manually. Do not change the approved camera, wind, current or rain settings to make this QA pass.

**Deferred polish:** deep-water current brightness/tint and small rain-angle irregularity remain design polish, not prerequisites for this integration phase.
