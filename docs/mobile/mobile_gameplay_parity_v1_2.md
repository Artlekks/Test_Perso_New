# Mobile Gameplay Parity & UI Polish v1.2

The optional mobile host retains 640x751 rendering at the iPhone 13 Pro reference size (390x844), KEEP_WIDTH and the existing 60/40 split. The gameplay image is 390x457.640625 logical/CSS pixels at (0,47). Controls begin at (0,504.640625), measure 390x305.359375, and end above the 34-point home inset. Desktop remains 640x480.

## Controls

Coordinates below are local to the controls region, in reference logical pixels. Add 504.640625 to Y for phone-window coordinates. Primary circles retain the existing rectangular ownership hit regions; secondary graphics are thinner inside unchanged hit regions.

| Button | Visible rectangle (x,y,w,h) | Hit rectangle (x,y,w,h) |
|---|---|---|
| A | 300.30,54.96,81.90,81.90 | same |
| B | 214.50,146.57,81.90,81.90 | same |
| C | 214.50,54.96,58.50,58.50 | same |
| L | 0,11,113.10,22 | 0,0,113.10,44 |
| R | 276.90,11,113.10,22 | 276.90,0,113.10,44 |
| MENU | 5.85,267.50,74.10,22 | 5.85,256.50,74.10,44 |
| SELECT | 136.50,267.50,78,22 | 136.50,256.50,78,44 |
| START | 218.40,267.50,78,22 | 218.40,256.50,78,44 |

Floating-stick zone remains (0,73.29,198.90,171.00); radius 56, deadzone 0.18. C does not intersect it. A remains K, B remains I, MENU remains J, START remains Space, SELECT remains reserved. C sends the same desktop C event into WorldInteractionRouter and TripleTriadOpponentNPC's existing challenge conversation. It does not add a card rotation binding (desktop rotation remains R). L sends Q, activating `cam_right`; R sends E, activating `cam_left`. A single canonical event also preserves existing raw-key consumers, without duplicate action events.

QA covers simultaneous C/A/B/stick ownership, independent releases, both named shoulder actions, canonical starter acquisition in a disposable save, C opening the real NPC conversation, confirmation opening the real Triple Triad game, and close restoring pause.

## HUD root causes and restoration

The previous adapter centered every CanvasLayer in a 480px UI band, offsetting it by 135.5px at height 751. Exploration HUD's production hide tween correctly moved its location widget to Y=-60, but that layer offset made it reappear at Y=75.5. Top HUDs now use the gameplay viewport directly, with no band offset. Their state logic and tween functions are unchanged.

PowerMeterView cached its `_rest_position` in `_ready()` while the bottom-anchored root was at Y=676. The post-ready adapter then froze its layout to desktop coordinates and added the 135.5px layer offset. The next slide-in animated back to cached Y=676, effectively drawing at Y=811.5, outside the 751px gameplay viewport. That same root contains power, tension and distance widgets.

The host now applies production HUD anchors before adding the gameplay scene to the tree, so all ready-time animation destinations use their final viewport geometry. Power root rests at Y=676, depth at Y=625; both stay inside the viewport. FishingHud, PowerMeter, ExplorationHud and FishingInfoView bypass the centered menu band. CharacterView and depth become bottom-anchored. Exploration HelpPanel retains the desktop bottom clearance, while compass/location remain at the actual top edges. Exploration notices move down by the additional viewport height; fishing notices retain their authored top position. Existing menus remain in their authored 640x480 band; dialogue continues to reflow to real viewport height. No replacement HUD or mobile visibility state machine was added.

The rendered comparison uses production mode signals, production power/depth/tension signals and their real animation functions. It holds the coordinator between snapshots, rather than claiming to be an end-to-end fish simulation. Separate full fishing regressions cover mechanics.

| State snapshot | Exploration location/compass/commands | Power/tension root | Tension marker | Depth |
|---|---|---|---|---|
| Exploration | shown | hidden | hidden | hidden |
| Entry/aim, before charge | hidden | hidden | hidden | hidden |
| Charge | hidden | shown | hidden | hidden |
| Airborne after power capture | hidden | shown | shown | hidden |
| IN_WATER after depth signal | hidden | shown | shown | shown |
| FIGHT, including left/right yaw | hidden | shown | shown | shown |
| Landing snapshot, before bait-return cleanup | hidden | shown | shown | shown |
| Result after bait-return cleanup | hidden | hidden | hidden | hidden |
| Exploration return after existing camera restoration | shown | hidden | hidden | hidden |
| NPC dialogue/choices from exploration | shown | hidden | hidden | hidden |

Desktop and mobile matched these snapshots. Cleanup timing, notices, character replacement and catch-result visibility remain production-owned; the table is not a new universal visibility policy.

## Fishing camera

CameraRig has one host presentation field, `mobile_fishing_vertical_offset`, defaulting to zero. The host calculates it from the authored FishingCameraPose, desktop projection, fishing h/v offsets and preserved exploration distance. It converts the extra vertical space into the v_offset required to retain desktop normalized foot Y. It does not move the player or change the camera transform's distance, pitch, horizontal offset, horizontal projection or tracking yaw parameters.

Measured desktop physical foot Y: 0.893650 (428.952/480). Measured mobile Y: 0.893650 (671.131/751). Additional mobile v_offset: 0.483804, yielding 1.133804 instead of the desktop 0.65. The physical actor projection, rather than an animation-frame edge, is the measurement. Left/right tracking preserves this normalized Y in runtime checks. Existing exit/restoration tween returns to the recorded exploration v_offset. There is no second return path.

## Dialogue Panel.png

The supplied file is an authored 32x48 tile atlas. `dialogue_panel_style.gd` assembles a 32x32 nine-slice from its regions in memory: four 8px corners from the top-left tile, top/bottom strips from the top-right tile, side strips from the middle-left tile, and 16x16 grain fill from the middle-right tile. StyleBoxTexture keeps 8px corners fixed and tiles edges/fill on both axes. The source PNG is unchanged and no new art file is generated.

The shared dialogue panel and portrait frame use this style. Choices remain inside that same textured dialogue surface. Body/speaker 18, choices 16, hints 10, nearest filtering, wrapping and measured expansion remain unchanged. Fishing/economy/card custom panels are untouched. Desktop production merchant dialogue, mobile merchant/card dialogue, and dialogue choices were rendered and inspected.

## Route discrepancy

Read-only local save inspection found desktop Baby Frog=1, Tail=1 and persisted Ocean/Lake flags. The local mobile playtest profile owns Straight/Wooden Rod and lacks Baby Frog. Safari has its own origin/device storage; its current save cannot be inferred from these Windows files.

Missing progression legitimately produces `Locked: ... Requires Baby Frog ownership`. The literal `Route unavailable` is a different branch: unknown destination, null authoritative current location, or an authored route that does not contain the destination. Both the real desktop and hosted mobile test scenes bind Beach and contain the Ocean destination. Fresh state has a locked sign, rather than that error; equivalent prerequisite ownership permits actual hosted travel. Scene replacement, context rebinding and persistent UI all pass.

The reported literal iPhone message was not reproduced. Its exact device-side cause remains incomplete; it cannot truthfully be attributed to missing unlocks alone. No route metadata, progression rules, save namespace, save data or unconditional mobile unlock was changed. Recheck after refreshing the rebuilt Web export; a persistent literal message needs the device's current context/build evidence.

## Verification

Godot used: `C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe`.

Commands used the following pattern, with per-run log files under the Codex visualization directory and isolated userdata where gameplay is booted:

```powershell
$godot = 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe'
# Windows GUI executable: Start-Process -Wait was used to wait reliably.
Start-Process -FilePath $godot -WindowStyle Hidden -Wait -ArgumentList '--headless --path . --max-fps 240 --quit-after 10000 --script res://scripts/qa/mobile_portrait_harness_qa.gd'
Start-Process -FilePath $godot -WindowStyle Hidden -Wait -ArgumentList '--path . --rendering-method gl_compatibility --max-fps 60 --fixed-fps 60 --quit-after 8000 --script res://scripts/qa/mobile_portrait_harness_qa.gd -- --rendered --capture-dir=<capture directory>'
Start-Process -FilePath $godot -WindowStyle Hidden -Wait -ArgumentList '--path . --rendering-method gl_compatibility --max-fps 60 --fixed-fps 60 --quit-after 6000 --script res://scripts/qa/mobile_gameplay_parity_qa.gd -- --rendered --capture-dir=<capture directory>'
Start-Process -FilePath $godot -WindowStyle Hidden -Wait -ArgumentList '--path . --rendering-method gl_compatibility --max-fps 240 --quit-after 8000 --script res://scripts/qa/dialogue_readability_qa.gd -- --rendered --capture-dir=<capture directory>'
Start-Process -FilePath $godot -WindowStyle Hidden -Wait -ArgumentList '--headless --path . --max-fps 240 --quit-after 10000 --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions'
Start-Process -FilePath $godot -WindowStyle Hidden -Wait -ArgumentList '--headless --path . --max-fps 240 --quit-after 40000 --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --mobile'
Start-Process -FilePath $godot -WindowStyle Hidden -Wait -ArgumentList '--headless --path . --max-fps 240 --quit-after 40000 --script res://scripts/qa/world_interaction_qa.gd'
Start-Process -FilePath $godot -WindowStyle Hidden -Wait -ArgumentList '--headless --path . --max-fps 240 --quit-after 40000 --script res://scripts/qa/world_location_access_qa.gd'
Start-Process -FilePath $godot -WindowStyle Hidden -Wait -ArgumentList '--headless --path . --max-fps 240 --quit-after 10000 --script res://scripts/qa/fishing_presentation_current_polish_qa.gd'
git diff --check
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1
```

Final results: mobile harness headless 150/150; rendered 157/157; production desktop/mobile parity rendered 53/53; dialogue rendered 121/121; desktop fight-camera/regressions 120/120; mobile fight-camera 116/116; full fishing 22950/22950; interaction 93/93; world-location 573 checks, zero failures; presentation/current polish 164/164; Triple Triad backend 101/101 during gameplay boot, plus the real touch-C match entry checks. Existing Fight 24/24, Presentation 10/10, Stability 27/27 and Fresh Save 55/55 remain green. Known provisional H12 guardrails remain 22/24, unchanged.

Rendered Compatibility runs still log the previously observed Godot `_save_to_cache` `f.is_null()` errors. They are not hidden or counted as a clean renderer log. No gameplay-script errors remain in the final runs. These are desktop-rendered reference tests, not physical iPhone verification.

## Files

- `assets/ui/Panel.png` (supplied by user)
- `assets/ui/Panel.png.import` (Godot import metadata)
- `scripts/camera_rig.gd`
- `scripts/dialogue/dialogue_view.gd`
- `scripts/dialogue/dialogue_panel_style.gd` and `.uid`
- `scripts/mobile/mobile_portrait_harness.gd`
- `scripts/mobile/mobile_touch_controls.gd`
- `scripts/qa/dialogue_readability_qa.gd`
- `scripts/qa/mobile_portrait_harness_qa.gd`
- `scripts/qa/mobile_gameplay_parity_qa.gd` and `.uid`
- `docs/mobile/mobile_gameplay_parity_v1_2.md`
- `export/index.html` and `export/index.pck` (rebuilt output)

The generated `export/index.*` build is overwritten by the helper. Git reports the HTML and PCK as changed; JS/WASM are regenerated but unchanged. HTTPS serving code/server are unchanged.

The helper was run after final QA and printed `Build complete: C:\Users\Alucard7th\Documents\FishingGame\fishing_game_clean_candidate_FRESH\export\index.html`. It exited successfully. No HTTPS server was started or restarted. `git diff --check` passed.

## Still needs device inspection

Refresh Safari and inspect power/tension/depth during a complete real cast/fight/landing/result cycle, camera composition through left/right runs, dialogue grain readability at phone scale, comfortable C/shoulder touches, multitouch, changing Safari chrome and safe-area clearance. The literal route-unavailable discrepancy needs device evidence if still present. Desktop rendered snapshots and headless mechanics tests do not substitute for that approval.
