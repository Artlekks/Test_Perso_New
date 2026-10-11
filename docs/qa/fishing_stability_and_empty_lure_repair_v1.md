# Fishing stability and empty-lure root-cause repair

## Baseline and scope

Audited the existing working tree against `bf60ae8` (HEAD), including all 17 already-modified scripts and both already-modified actor scenes. The warning cleanup is uncommitted; Git history does not identify a separately verified last-working revision. HEAD's description itself says the camera is broken, so it is a comparison baseline, not a claim of historical health.

The parameter/local renames in developer service, development layer, merchant menu, info view, mobile harness, deck setup, modal ownership, grounding and marker scripts are behavior-equivalent. The gathering/salvage enum substitutions retain their numeric values. The unused debug-menu local deletion is harmless. Kept these changes rather than discarding authored work. Kept the encounter's weak ambient-shadow reference and replacement checks: these fix an asynchronous lifetime issue and passed the scene/lifecycle suites. The safe-region overlay's surface/physical dots are diagnostic-only. Neither actor scene was edited in this repair.

## Reproduced causes and repairs

1. **Editor compilation/load-order cycle.** `FishingRegressionHarness._test_debug_persistence_gate_regression()` references `FishingDebugController`. That controller preloaded `FishingDebugMenu.tscn`, whose script references `FishingRegressionHarness`. Restoring the saved editor script layout reproduced `Parse Error: Busy` at `FishingDebugMenu.tscn:19` and Windows exit `3221225477`, in both HEAD and current snapshots. A clean first import of either snapshot passed, explaining the intermittent editor-only failure. `FishingDebugController.configure()` now loads its optional menu at composition time and still reports a failed load explicitly. Actual working-tree import with the same saved layout now exits 0 with no parser/runtime errors. No editor cache was deleted or warnings disabled.

2. **Fish class diagnostics.** `fish_instance.gd` still declares `class_name FishInstance`; `fish_spawn_entry.gd` still exports `fish: FishData`. Neither definition changed in the cleanup. Clean imports and `world_location_access_qa.gd` resolve both successfully (600/600). No QA reference or class filename was changed. The precise historical unresolved-class diagnostic was not reproduced; the reproduced incremental load cycle is a plausible cascade source, not proof that it caused every previously reported class error.

3. **First arc redirected by physical screen envelope.** The old empty-lure guard began at x=34%, y=35% and ended at x=76%. Valid visible landings outside that interior band triggered the candidate solver, which preferred straight inward recovery over the requested tangent. The actual Caster/Bait fixture reproduced four wrong-direction left cases. The physical guard now uses x=10–90%, y=5–77%, with existing small guard margins; the near-shore pocket expands toward the real water-side landing projection and cannot shrink an already wider region. This physical visibility guard is independent of the camera response band.

4. **A signed world tangent was insufficient.** Orthogonalizing a screen-right direction against the inward vector made the tangent valid, but the inward vector itself projected left. Before compensation, D at (320,150) and (470,150) projected x deltas of approximately -0.003 and -0.066 pixels respectively despite positive tangent contributions. `FishingScreenLateral.retrieve_direction()` accounts for both projected contributors. Compensation is bounded at 4 (at least 1/sqrt(17) inward authority); finite arc steps are bounded by radius times inward authority. Empty-lure steering remains immediate; discrete twitch no longer adds a conflicting free-lure impulse. Fight steering, twitch, resistance, stamina and tension calculations remain untouched.

5. **Shore and HUD ownership disagreement.** Empty retrieves now aim at the existing shoreline's water-side projection, rather than a dry-land target that the shore solver rejects. Caster binds the camera's live viewport/HUD-region callback into each bait. Bait's physical guard and the camera invariant therefore use the same actual power-bar geometry and 12-pixel clearance. No copied shell HUD location or altered UI layout.

6. **Empty-lure camera policy leaked into hooked combat.** The working-tree camera change replaced the established fight path with right-only, 7-degree surface tracking. The fight-camera suite returned 174/197. Restored HEAD's hooked/generic target composition and 55-degree cap inside the same camera owner. Empty lures retain the newer exact global-pose water handoff, ANCHORED state, restrained 7-degree yaw, surface projection and existing exponential retrieve return. Actual IN_WATER-to-FIGHT ownership stays on the same physical bait; no second controller or reset service.

## Focused coverage

`empty_lure_retrieval_qa.gd` uses the actual session, authored Caster/Bait scene, starter loadout, shore boundary and input handlers with isolated saves. Deliberately runs the first physics step before idle polling. Covers legal and invalid behind-HUD starts, both directions, K, nine sustained retrieves, near-shore curvature, zero stalled ticks, player composition, ANCHORED pose continuity, exact retrieve restoration, live HUD counters, authored current/action contributors, all 40 lure profiles in both directions, and actual authored flight/landed-signal ordering at powers 0.3/0.6/0.9. Latest result: **205/205**. Sustained retrieves exercised approximately 7,000 physics ticks, with no stalls in the nine completion cases.

`fishing_water_camera_qa.gd` now explicitly identifies its fake target as an empty lure; generic targets correctly exercise the restored fight path instead.

`passive_fishing_qa.gd` had nine failures from an obsolete aerial depth-12 bait fixture and old fight-camera expectations. Its camera subfixture now uses water-plane ray intersections, actual bait physics and a scene-owned deterministic current. It retains checks for focus/lease ownership, quiet safe framing, actual viewport/HUD containment, modest yaw, safe reentry, no bite bypass, save integrity and orphan-free teardown. Current fixture and action state are restored afterward.

## Commands and results

Executable: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe` (actual 4.7.2). Runs used disposable APPDATA/LOCALAPPDATA under `build/mobile-web/root-repair`, with each runtime fixture's additional isolated save directory. Commands below are executable arguments; the ignored Python wrapper captures stdout, stderr and exit codes.

| Arguments | Result |
|---|---|
| `--headless --path . --editor --import --quit` | Exit 0; saved layout reopens; no SCRIPT ERROR / ERROR |
| `--headless --path . --script res://scripts/qa/empty_lure_retrieval_qa.gd` | 205/205 |
| `--headless --path . --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd` | 199/199 |
| `--headless --path . --script res://scripts/qa/fishing_water_camera_qa.gd` | 16/16 |
| `--headless --path . --script res://scripts/qa/fishing_camera_reconstruction_qa.gd` | 124/124; two deliberately provoked firewall errors expected |
| `--headless --path . --script res://scripts/qa/passive_fishing_qa.gd` | 95/95 |
| `--headless --path . --script res://scripts/qa/session_contract_runner.gd` | 22,950/22,950; runner PASS, orphan nodes 0 |
| `--headless --path . --script res://scripts/qa/world_location_access_qa.gd` | 600/600 |
| `--headless --path . --script res://scripts/qa/world_interaction_qa.gd` | 93/93 |
| `--headless --path . --script res://scripts/qa/beach_collision_qa.gd` | 65/65 |
| `--headless --path . --script res://scripts/qa/runtime_lifecycle_qa.gd` | 1,832/1,832 |
| `--headless --path . --script res://scripts/qa/runtime_lifecycle_qa.gd -- --mobile` | 1,052/1,052 |

Session suite includes Fight 24/24, Presentation 10/10, Bite Timing 14/14, System Stability 27/27, Triple Triad backend 101/101, Crafting 14/14, Campaign 14/14 and Fresh Save 55/55. Dedicated economy guardrails remain **22/24**, with the two existing H12 balance warnings visible; no economy target/value changed.

Final Web rebuild used `& .\tools\mobile\build_mobile_playtest.ps1` with the existing Linux/WSL helper, without restarting HTTPS. Final artifact validation: PCK **32,534,100 bytes**; `project.binary` **9,970 bytes**, **ECFG**. Build completed successfully.

`git diff --check` exited 0. Git reports only normal CRLF-to-LF normalization notices. The two deliberately provoked reconstruction firewall errors are confined to its negative tests; normal import, focused retrieval, full/session, world, interaction, collision and lifecycle logs contain no SCRIPT ERROR or ERROR lines. Intermediate failures are described above; no failed run is counted as a pass.

## Files changed by this repair

- `scripts/bait_V2.gd`
- `scripts/camera_rig.gd`
- `scripts/caster.gd`
- `scripts/fishing.gd`
- `scripts/fishing_debug_controller.gd`
- `scripts/fishing_screen_lateral.gd` (already untracked at start; extended)
- `scripts/qa/fishing_water_camera_qa.gd` (already untracked at start; target classification corrected)
- `scripts/qa/empty_lure_retrieval_qa.gd` and generated `.uid`
- `scripts/qa/passive_fishing_qa.gd`
- this report
- generated `export/index.html` and `export/index.pck`

Other dirty files predated this repair and were preserved. No original script was renamed, no safety check disabled, no gameplay UI/economy/scene authored placement changed.

## Remaining acceptance / limits

No physical Safari playtest was performed in this repair. Headless execution verifies actual input, production movement, scene lifetime and projected camera geometry; it does not establish visual feel. Check first A/D immediately after a real landing, continuous near-shore curves, a hard-left/right retrieve, K straight retrieve, catch-result dismiss, and a hooked fight on the phone. The projection compensation is deliberately bounded: at a hard visibility/shore limit, inward progress and HUD safety take priority over an indefinitely outward screen direction. Exact historical FishInstance errors remain unattributed beyond the reproducible dependency-cycle finding.
