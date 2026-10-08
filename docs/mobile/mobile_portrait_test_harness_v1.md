# Mobile Portrait Test Harness v1

## Launch and scope

Open `actors/mobile/MobilePortraitHarness.tscn` in Godot and press F6. F5 still launches the ordinary desktop game. CLI equivalent:

```powershell
& 'C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe' --path . res://actors/mobile/MobilePortraitHarness.tscn
```

This is an optional input/presentation host, not a full mobile port. It follows the supplied mockup's black upper area, grey controls, diagonal A/B, shoulder pads and lower button row. It uses ordinary drawn UI, no generated art or changes to existing sprites. Existing gameplay, camera, transaction, progression, save schemas and desktop bindings remain authoritative.

The shell uses a separate `FishingGame-MobilePortraitPlaytest` userdata folder by default, created before game bootstrap. Its normal gameplay can save playtest progress there; it never selects the desktop save folder. QA uses unique disposable folders instead. No export was published or deployed.

## Architecture

- Portrait reference: 390×844 logical points, iPhone 13 Pro proportions.
- Safe area: actual native DisplayServer safe rectangle; Web CSS `env(safe-area-inset-*)`; desktop reference fallback top 47/bottom 34. Hardware pixels are converted into logical coordinates. A constrained portrait column handles wide windows/rotation.
- Larger-gameplay/dialogue v1.1 supersedes the width-only 4:3 presentation. Mobile keeps 640 logical pixels horizontally and derives its logical height from 60% of actual safe height, reserving at least 280 CSS/reference points for controls at 390-point width. Gameplay is uniformly scaled with nearest filtering at full portrait safe width and top aligned. Controls start immediately below it. Landscape preview retains its centered portrait column.
- iPhone 13 Pro reference (390×844 logical/CSS pixels, top inset 47, bottom inset 34): safe height 763; derived gameplay resolution **640×751**; displayed gameplay rectangle `(0, 47, 390, 457.640625)`; controls `(0, 504.640625, 390, 305.359375)`, ending at y=810. Split: 59.98% / 40.02%. Safari chrome can reduce gameplay height to retain comfortable controls; dimensions are measured, not hardcoded.
- All hosted Camera3Ds use KEEP_WIDTH with the equivalent horizontal FOV of their original 640×480 projection. This reveals more vertical world without horizontal zoom or cropping. Camera transforms, desktop camera resources and mechanics stay authored. Existing HUD/menu art retains its 640×480 geometry in a centered band within the taller viewport; fishing vertical screen thresholds are mapped to that same band in the mobile context. Item-selector viewport coordinates are converted back to their parent canvas space, preserving alignment in a translated band.
- A SubViewport with its own 3D and 2D worlds hosts the existing game scene. Game processing remains pausable. The shell uses an independent always-processing canvas for the lower touch panel.
- Persistent session data/services retain their existing `/root/FishingSessionServices` location. Their presentation CanvasLayers are hosted in the gameplay viewport and are returned with original layout/offsets to their original parents when the shell exits. Shared dialogue uses the taller viewport's bottom margin and measured reflow.

Godot requires `SceneTree.current_scene` to be a direct root child. Assigning a SubViewport child there is invalid. The shared `scripts/gameplay_scene_root.gd` resolver returns the wrapped game when a scene host provides `get_gameplay_scene()`, otherwise it returns the ordinary desktop `current_scene`. Existing scene lookups use that one resolver; there are no mobile versions of gameplay systems. The change in those existing files is limited to a preload and equivalent scene-root lookup expressions.

The same adapter supplies scene loading. WorldLocations retains all existing route, unlock, busy and fishing-ownership guards, then delegates its existing scene-load operation to the adapter. The optional host replaces the game inside its viewport. Desktop still calls `SceneTree.change_scene_to_file`. This keeps travel and persistent UI inside the shell without duplicating progression or rerunning gameplay readiness through reparenting.

## Touch mappings

| Touch | Existing input |
| --- | --- |
| A | K / `enter_fishing`: interaction, confirm, cast, reel |
| B | I / `cancel_fishing`: existing back/cancel |
| MENU | J: existing game/fishing menu |
| START | Space: existing manual pause controller, including its pause ownership guard |
| L | Q / existing `cam_right`, and existing previous category/tab handlers |
| R | E / existing `cam_left`, and existing next category/tab handlers |
| SELECT* | Reserved, no event; marked on the panel |
| Floating stick | W/A/S/D navigation; `move_forward/back/left/right`, plus `ds_left/right` fishing steering |

The current game mixes InputMap action consumers and raw-key dialogue/menu/router consumers. Buttons feed one canonical existing key event through the normal input path, which also activates the InputMap action; they do not send a second confirmation action event. The stick sets the existing analog action strengths and dispatches canonical navigation key edges through the viewports without adding a competing full-strength digital source. This preserves analog intent and legacy navigation. Gameplay input ownership stays with the existing controllers.

The stick appears at the first finger's position within the lower-left zone, clamps its knob to a 56-point radius, uses a 0.18 deadzone and hides on release. Actual exploration still uses its existing eight-direction movement rules. Fingers have independent IDs; a second finger can hold A while the stick moves. Multiple fingers on the same button are reference-counted. Release, cancellation, focus loss, resize and scene replacement clear owned input. Mouse click/drag provides an optional desktop preview; emulated touch mouse events are excluded to avoid double presses.

Easy Inspector tuning: reference size, safe-inset fallback, gameplay-height share, minimum controls height, targeted mobile economy font sizes, gameplay scene and isolated save toggle on the shell; stick radius/deadzone/mouse testing on controls. A/B placement is adjusted for the shorter panel with no overlapping hit rectangles. Utility/shoulder targets have at least 44 reference points of height at 390-point width. Stick radius/deadzone/mappings/reference counting remain unchanged.

Shared dialogue body and speaker text now use **18** (previously 9); choices **16** (previously 8); hints **10** (previously 7), retaining the BOF bitmap font and nearest filtering. The 512-wide box keeps its 38-point bottom margin and expands upward according to measured wrapped text plus Label line spacing, rather than its old fixed 86/116 heights. Body/choices use a VBox in a scroll container for oversized future content. Choice selection ensures its line remains visible. No additional mobile multiplier is applied to dialogue. Mobile-only merchant/trade row, info, requirements and confirmation text use size 12; small notices/wallet/help use 10, with widened requirement/details space. Fishing menu/help and catch-result text retain existing authored 2x treatment; campaign guide and small HUD hints retain their own typography. These exceptions still need phone readability judgment.

## Phone workflow

The easiest Windows iteration path is the included **Mobile Portrait Web Playtest** export preset. It supplies the optional `mobile_portrait` feature, which selects this main scene, portrait dimensions/orientation and Compatibility renderer only for that build. Desktop settings remain unchanged. The preset uses single-threaded Web export and disables PWA caching for early iteration.

1. In Godot, install export templates matching **4.7.2.stable** through Manage Export Templates.
2. Build the **Mobile Portrait Web Playtest** preset into `export/index.html` with the Windows helper. It resolves the project from its own script path, uses the installed Godot 4.7.2 executable, waits for completion, and reports export failures. From the project directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1
# In a separate terminal, start HTTPS once (skip if already running):
& 'C:/Users/Alucard7th/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/mobile/serve_playtest.py --directory export
```

3. Put the phone and PC on the same development Wi-Fi. Open the exact `https://<LAN_IP>:8060/` address printed by the helper in Safari. The default bind is `0.0.0.0`; use `--host <PC Wi-Fi IPv4>` if automatic address detection selects a VPN/other adapter. Allow the development server through Windows Firewall on that private network if prompted. Stop it with Ctrl+C.
   On the first visit, Safari warns about the self-signed development certificate. Choose Show Details, then visit this website/Continue and confirm (labels vary; a passcode may be required). A warning bypass alone may not grant a secure context. If Godot still reports that warning, download the public certificate from the printed `/__playtest__/certificate.cer` URL, install its downloaded profile in Settings → General → VPN & Device Management, then enable full trust in Settings → General → About → Certificate Trust Settings. Reopen Safari. Trust only this PC's development certificate; remove the profile after playtesting. Repeat if the certificate renews or the LAN IP changes. See [Apple's manual certificate trust instructions](https://support.apple.com/en-gb/102390).
4. Keep HTTPS running. After every project edit, run the same single build command, wait for **Build complete**, then refresh Safari at the same address. The builder overwrites the existing export without starting/stopping a server. Do not refresh while exporting, because the export contains multiple files updated in place.
   Completed mobile-specific implementation passes should run this build automatically after QA and wait for completion. They must leave the existing HTTPS server running.
   The server serves correct WASM MIME type and sends `Cache-Control: no-store, no-cache, max-age=0, must-revalidate`, `Pragma: no-cache`, and `Expires: 0` for HTML/JS/PCK/WASM and other responses. Conditional requests get fresh content rather than 304 responses, including quick successive builds. If your server was running the older Python helper, restart that process once to load the updated headers; future Web rebuilds need no restart.
   Use the direct page rather than an iframe. Test portrait with Safari chrome shown/hidden, notch/home-indicator clearance and interrupted touches. Browser persistence requires available site storage; treat it as playtest data.

The helper uses Python plus `cryptography` to generate/reuse a self-signed TLS certificate and private key. Install it for your interpreter with `python -m pip install cryptography` if missing. The bundled interpreter already has it: `C:/Users/Alucard7th/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`. TLS files live in `%LOCALAPPDATA%/FishingGame/mobile-playtest-tls` (or `~/.cache/FishingGame/mobile-playtest-tls` outside Windows), never in the exported game. Certificates include the detected LAN IP, localhost and loopback, expire after a year, and are reused while valid. Only the public certificate is downloadable; the key stays outside the served directory. This server is exclusively for local development/playtesting and does not alter export files.

Official Godot docs recommend single-threaded export for simpler Web hosting and iOS browser compatibility; Web requires the Compatibility renderer. Native iOS needs a Mac/Xcode/signing workflow. For later native export, use the same shell and add `mobile_portrait` to an iOS preset rather than changing the desktop main scene. Web/native performance and Safari behavior still need device testing. Sources: [Godot Web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html), [Godot iOS export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html).

## Actual verification and limitations

Larger-gameplay/global-dialogue v1.1 verification: mobile harness 124/124 headless and 130/130 rendered; dialogue readability 119/119 (catalog lines, all master flavor profiles, desktop/mobile wrapping, selector and overflow containment); mobile aspect water/fight camera 116/116; desktop camera plus regression 120/120; full fishing 22950/22950. Existing startup dialogue 175/175, economy foundation 13/13, Campaign Loop 14/14 and Fresh Save 55/55 remained green. Known economy simulator balance guardrails remain 22/24. Rendered gameplay, equipment, dialogue, merchant and catch screens were inspected in Godot. The GLES3 rendered game run still logged shader-cache `_save_to_cache` errors. Actual phone readability, Safari chrome transitions, fishing entry/cast/water/fight/catch composition and GPU performance need iPhone judgment. Extra vertical world reveals authored beach geometry edges/void; these are inside the world render rather than outer shell gutters. No source sprites were modified.

Commands for this pass (using the installed Godot executable and isolated external logs/captures):

```powershell
& $godot --headless --path . --max-fps 240 --quit-after 8000 --script res://scripts/qa/mobile_portrait_harness_qa.gd
& $godot --path . --rendering-method gl_compatibility --max-fps 60 --fixed-fps 60 --quit-after 1500 --script res://scripts/qa/mobile_portrait_harness_qa.gd -- --rendered --capture-dir=$captures
& $godot --path . --rendering-method gl_compatibility --max-fps 240 --quit-after 8000 --script res://scripts/qa/dialogue_readability_qa.gd -- --rendered --capture-dir=$captures
& $godot --headless --path . --max-fps 240 --quit-after 40000 --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --mobile
& $godot --headless --path . --max-fps 240 --quit-after 40000 --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions
& $godot --headless --path . --max-fps 240 --quit-after 40000 --script res://scripts/qa/world_interaction_qa.gd
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1
git diff --check
```

Earlier width-only layout verification: 70/70 headless and 73/73 rendered. That pass kept 640×480 at 390×292.5 and did not rebuild the export. It has now been superseded by the taller viewport above.

Headless mobile QA passed 51/51. It runs the real wrapper/game with isolated userdata and covers scene identity, viewport/camera containment, session dialogue containment, safe rectangles, button hit regions, native ScreenTouch/Drag coordinate transforms, real player movement, analog strength, simultaneous A/stick, independent release, existing menu/dialogue/pause/cast routing, SELECT reservation, shoulders, multiple fingers per button, deadzone/radius, focus loss and scene replacement. It also exercises real progression-guarded Beach-to-Ocean travel, including locked and duplicate request rejection and persistent UI containment.

Commands run (with external artifact `--log-file` paths):

```text
godot --headless --path . --max-fps 240 --quit-after 8000 --script res://scripts/qa/mobile_portrait_harness_qa.gd
godot --path . --rendering-method gl_compatibility --max-fps 60 --fixed-fps 60 --quit-after 1500 --write-movie ARTIFACT.avi --script res://scripts/qa/mobile_portrait_harness_qa.gd -- --rendered --capture-dir=ARTIFACT_DIRECTORY
godot --headless --path . --max-fps 240 --quit-after 40000 --script res://scripts/qa/world_interaction_qa.gd
godot --headless --path . --max-fps 240 --quit-after 40000 --script res://scripts/qa/beach_collision_qa.gd
godot --headless --path . --max-fps 240 --quit-after 40000 --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions
godot --headless --path . --quit-after 40000 --script res://scripts/qa/world_location_access_qa.gd
godot --headless --path . --quit-after 40000 --script res://scripts/qa/early_tackle_acquisition_qa.gd
godot --headless --path . --quit-after 40000 --script res://scripts/qa/runtime_economy_reconciliation_qa.gd
python tools/mobile/serve_playtest.py --help
git diff --check
```

Desktop results: interaction 93/93; beach collision 65 checks/zero failures; full fishing 22950/22950; fight camera 120/120; Fight 24/24; Presentation 10/10; Stability 27/27; world location 573 checks/zero failures; acquisition 61 checks/zero failures; current reconciliation suite 1002/1002. The existing two provisional H12 balance alerts remain visible (22/24 guardrails), along with the expected Triple Triad backend guard warning.

The final rendered Compatibility run passed 54/54, including three actual pixel checks proving the control panel remains visible in gameplay, menu and merchant dialogue. The panel is independently rendered while paused. Captures were inspected; this is desktop rendered evidence, not phone visual approval. The local Godot renderer logged shader-cache `_save_to_cache` file-write errors; these were not suppressed.

Export was attempted and failed because `web_nothreads_debug.zip` and `web_nothreads_release.zip` are missing under `Godot/export_templates/4.7.2.stable`. No runnable Web/iPhone build was produced here. Safari/native safe-area APIs, browser multitouch, actual iPhone performance and audio remain untested. Installing templates and running the phone workflow above is the next concrete step.

Readability: all authored panels fit the gameplay view. Menu headings/large labels are readable in desktop portrait captures; dialogue body text, confirmation hints and small HUD text become roughly 6–8 logical points at 390-point phone width. They likely need a later isolated mobile readability pass. This harness intentionally does not enlarge global UI or crop the game to hide that finding.

## Changed files

The complete list follows. Existing gameplay-file edits are scene-host binding changes only.

- .gitignore
- actors/mobile/MobilePortraitHarness.tscn
- docs/mobile/mobile_portrait_test_harness_v1.md
- export_presets.cfg
- project.godot
- scripts/beach_crafter_npc.gd
- scripts/beach_crafting_feel_qa_hud.gd
- scripts/beach_gathering_circuit.gd
- scripts/beach_gathering_node_3d.gd
- scripts/beach_merchant_npc.gd
- scripts/dialogue/dialogue_npc_bridge.gd
- scripts/economy/fishing_card_maker_npc.gd
- scripts/economy/fishing_card_maker_service.gd
- scripts/fish_zone_v2.gd
- scripts/fishing_economy_menu.gd
- scripts/fishing_info_view.gd
- scripts/fishing_menu.gd
- scripts/fishing.gd
- scripts/gameplay_scene_root.gd
- scripts/gameplay_scene_root.gd.uid
- scripts/mastery/fishing_master_lesson_npc_base.gd
- scripts/mastery/fishing_master_still_water_npc.gd
- scripts/mobile/mobile_portrait_harness.gd
- scripts/mobile/mobile_portrait_harness.gd.uid
- scripts/mobile/mobile_touch_controls.gd
- scripts/mobile/mobile_touch_controls.gd.uid
- scripts/progression/fishing_reward_claim_npc_base.gd
- scripts/progression/playable_campaign_presentation_controller.gd
- scripts/progression/playable_campaign_progression_director.gd
- scripts/qa/mobile_portrait_harness_qa.gd
- scripts/qa/mobile_portrait_harness_qa.gd.uid
- scripts/quests/beach_crafter_request_source.gd
- scripts/quests/card_maker_fishing_request_source.gd
- scripts/quests/world_objective_tracker.gd
- scripts/telemetry/runtime_economy_telemetry.gd
- scripts/triple_triad/triple_triad_acquisition_trigger.gd
- scripts/triple_triad/triple_triad_competition_interaction_3d.gd
- scripts/triple_triad/triple_triad_developer_tools_controller.gd
- scripts/triple_triad/triple_triad_fishing_salvage_bridge.gd
- scripts/triple_triad/triple_triad_harbor_request_board.gd
- scripts/triple_triad/triple_triad_opponent_npc.gd
- scripts/triple_triad/triple_triad_quest_reward_adapter.gd
- scripts/triple_triad/triple_triad_world_reward_trigger_3d.gd
- scripts/triple_triad/triple_triad_world_reward_trigger.gd
- scripts/world/manillo_trader_npc.gd
- scripts/world/world_location_service.gd
- tools/mobile/serve_playtest.py
