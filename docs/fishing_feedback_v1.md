# Fishing Feedback Fix v1 — verified 2026-10-09

## Behavior and causes

Camera return now uses `1-exp(-fight_yaw_return_response*delta)`, the existing tracker neutral-response smoothing (2.0), around the same player pivot and captured post-aim child-camera transform. No fixed duration remains. Stop tolerance is `retrieve_yaw_stop_degrees=0.05`; measured 5-degree and 55-degree returns settle in 2.317 and 3.517 seconds at 60 Hz. Retrieval and real K catch dismissal use the same return owner. Centered shots do not start a return. Tracking bounds, +/-55-degree limit, cast/entry behavior, A/D aim, radius, pitch and FOV were not changed.

The hook-ready presentation cue previously replaced the ripple before the opportunity ended, immediately for direct-commit bites. The ripple also used a small fixed-size pixel scale. The opportunity now keeps the ripple through the hook-ready character cue; only confirmed `bite_triggered` switches to the stronger existing `bait_bite_sheet.png` one-shot. Miss/end clears it. Character Reel_Front/strong-take behavior remains.

The exact ripple source is `assets/sprites/fishing/bait/fish_ripple.png` (11904x127), authored in `actors/bait_V2.tscn`, `SpriteFrames_l3qxs`, animation `Ripple`: 48 frames, 248x127 each, 20 FPS, 2.4 seconds. Runtime uses cached, decompressed individual authored frame textures so cropping works on rendered VRAM-compressed imports and does not depend on the oversized atlas fitting the mobile GPU. This is a portability correction; an iPhone GPU limit was not proven as the cause. Ripple pixel size is 0.0035. Each non-looping playback is fitted to Encounter's existing species-dependent opportunity duration (ordinary base 0.8 seconds); no bite timing policy, species multiplier or hook threshold changed.

The original beach bottle candidates were (-1.602337,0.08,-4.090945), (0.097663,0.08,-4.790946), (1.397663,0.08,-4.290945). These were beyond practical starter casts. New authored candidates are (-0.702337,0.08,-2.240945), (0.097663,0.08,-2.440945), (0.597663,0.08,-2.240945). The Wooden Rod and 0.95 acquisition radius are unchanged. Legal cast-ready QA samples +/-60-degree aim and 0..1 power through the production predictor, including the screen-space rod spawn at each heading, from center and +/-0.8m shore stances. All candidates have 0.012..0.067 landing error and pass the actual marker trigger. Eligibility, 3-5 catches, intentional cast, successful catch and one-shot card grant remain unchanged.

## Final commands and actual results

Native Godot executable: `C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe`. Native executable invocations were awaited with `Start-Process -WindowStyle Hidden -Wait`; parallel independent suites used equivalent process waits. Logs are under `build/mobile-web/feedback-*.log`.

| Godot arguments / command | Result |
| --- | --- |
| `--headless --path . --script scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions` | Camera 168/168; full fishing 22950/22950 |
| `--headless --path . --script scripts/qa/fishing_fight_camera_tracking_qa.gd -- --mobile` | 164/164 |
| `--headless --path . --script scripts/qa/fishing_presentation_current_polish_qa.gd` | 194/194 |
| `--path . --rendering-method gl_compatibility res://actors/mobile/FishingFeedbackQA.tscn` | 34/34; actual K dismissal, nine casts, ripple lifetime and rendered pixel comparison |
| Actual Linux Web export of `FishingFeedbackQA.tscn`, loopback port 8076 | 34/34; native and Web reachability results agree; 939 changed ripple pixels on final 390x844 browser reference run |
| `--headless --path . --script scripts/qa/mobile_portrait_harness_qa.gd` | 182/182 |
| `--headless --path . --script scripts/qa/world_location_access_qa.gd` | 586 checks, 0 failures |
| `--headless --path . --script scripts/qa/early_tackle_acquisition_qa.gd` | 61 checks, 0 failures |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1` | Final Linux/WSL production build succeeded; PCK 31972256 bytes; project.binary 9944 bytes, ECFG |
| `git diff --check` | Clean |

Existing Fight 24/24, Bite Timing 14/14, Presentation 10/10, Stability 27/27, Fresh Save 55/55 also passed. Native rendered logs retain existing GLES shader-cache `f.is_null()` errors; Web logs retain expected provisional H12 balance warnings (22/24), which are not failed feedback checks. No balance values changed.

Web QA used a disposable loopback origin, with the main scene changed only in the dedicated Linux mirror under a finally/restoration guard. Production and Windows main scenes remain MobilePortraitHarness. The temporary browser tab and HTTP QA server were closed; HTTPS was never started or restarted. Native reference uses 390x844 and 47/34 safe insets (game viewport 640x863); desktop Web has its browser-provided safe area, so it is not a physical Safari test. Physical iPhone acceptance remains needed for perceived unwind speed and ripple readability.

## Complete changed/new files for these fixes

- scripts/bait_V2.gd
- scripts/camera_rig.gd
- scripts/caster.gd
- scripts/fishing.gd
- scripts/ripple_view.gd
- scripts/triple_triad/triple_triad_fishing_salvage_bridge.gd
- scripts/qa/fishing_fight_camera_tracking_qa.gd
- scripts/qa/fishing_presentation_current_polish_qa.gd
- scripts/qa/fishing_feedback_v1_qa.gd (new)
- scripts/qa/fishing_feedback_v1_qa.gd.uid (new)
- actors/mobile/FishingFeedbackQA.tscn (new, dormant production QA fixture)
- docs/fishing_feedback_v1.md (new)
- export/index.html
- export/index.pck

No source PNG, rod stats, acquisition radius, save schema, input mapping, HUD, shadow, collision or HTTPS serving code was changed.
