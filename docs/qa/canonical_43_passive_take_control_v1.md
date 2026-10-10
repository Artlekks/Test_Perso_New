# Canonical 4:3 Gameplay Surface + Passive Take-Control v1

## Delivered behavior

Previous world surface: **640x864**. New shared world surface: **640x480 (4:3)**, defined in `scripts/ui/canonical_game_surface.gd`. Its separate `MENU_SIZE` remains 640x864. `PortraitUI.SIZE` now explicitly refers to that menu size, not camera geometry.

Normal desktop and fullscreen use the 640x480 logical canvas with uniform letterboxing. Phone and companion use a 640x480 SubViewport. The tall-camera adapter was removed: no FOV conversion, extra vertical composition offset, HUD Y shift, or device-specific safe-frame remapping remains. Authored camera distance, pitch, FOV/aspect policy, aim, water/fight ownership and retrieve return are retained.

At 390px safe phone width the game image is **390x292.5 logical/CSS pixels**. It starts immediately beneath the actual safe-area inset, with controls immediately below it and home-indicator clearance retained. The same full image fits both 390x844 and short 390x664 references; no world crop or non-uniform scaling. Safari CSS safe-area values take precedence over native-reference fallbacks.

Companion game image starts below its existing 68px chrome. Its existing taller shell/window dimensions are retained independently, leaving room below the 4:3 world. Float, Dock Left, Dock Right and collapse geometry remain independent of activity. This does not implement a second-screen redesign.

## Camera edge contract

Exports in `scripts/camera_rig.gd`:

| Bound | Normalized | 640x480 pixel coordinate |
|---|---:|---:|
| Left | 0.18 | 115.2 |
| Right | 0.82 | 524.8 |
| Top | 0.22 | 105.6 |
| Bottom | 0.70 | 336 |

The inclusive safe rectangle immediately sets HOLD and returns the exact existing yaw, even if an edge latch was active. Crossing left/right starts the corresponding pan; reentering anywhere in the rectangle stops it immediately. Traversing center toward the opposite edge causes zero yaw until that edge is crossed. No neutral unwind inside the rectangle. Existing vertical/HUD protection still applies outside the rectangle. The remaining 0.02 search margin is a convergence target only; it cannot prolong pan after safe-rectangle entry.

Response 6, return response 2 and maximum yaw +/-55 degrees are unchanged. The physical active bait remains the target in IN_WATER and FIGHT, independent of presentation visibility. Retrieve/catch-result return is still the existing separate restoration flow.

## Passive handoff

The companion intercepts a fresh, non-echo K/enter_fishing press while Passive and unpaused. It calls the existing `set_mode(ACTIVE)`, consumes the outer event, then pushes that same event exactly once into the existing gameplay SubViewport. No session, bait, camera or current is recreated. Normal fishing input owns the reel/hook/cast action after transfer; key release also reaches the normal owner. Paused interfaces retain their input ownership.

Timer configuration is confirmed with Enter. K during configuration also means takeover. The timer remains in the surrounding companion shell beneath the world image.

When the existing focus-plus-opportunity schedule produces a persistent opportunity, READY is established first, then the host switches Active. Existing activate() retains that lease as HANDOFF, keeping the hook window non-punitive until the player responds. Collapsed geometry does not expand as a side effect. Normal cancellation/travel cleanup remains intact.

## UI migration

- Exploration/location/compass and power/depth/tension use original 480px authored positions and tween destinations.
- Line/bait rendering stays in the unchanged physical world, projected through 4:3.
- Dialogue and composed catch result use the actual 640x480 HUD canvas on mobile; catch centering excludes controls/chrome.
- Merchant, fish trade, crafting, Card Maker and inventory retain their existing menu presentation. Responsive menus measure their explicit menu canvas rather than assuming it equals world height.
- Companion menus use a separate transparent 640x864 canvas over the existing shell. Retained session layers return to their original viewport before shell destruction, preventing stale viewport ownership.
- Mobile tall menus keep the existing shell gutter scrolling; scrolling changes the menu image only, never the world image/camera.
- Triple Triad keeps the existing 640x864 card layout on shell menu canvases. On ordinary desktop it uniformly fits its menu canvas independently of the 4:3 world; no card rules or ownership changed.
- Developer indicator stays within the restored world height. Controls and mappings are unchanged.

## Final QA results

| Suite | Result |
|---|---:|
| Camera native | 187/187 |
| Camera mobile configuration | 187/187 |
| Rendered mobile real cast/edge/miss/hook/land/retrieve journey | 1344/1344 |
| Rendered companion journey | 1388/1388 |
| Rendered Web journey, verified new surface43 basename at 390x664 | 1344/1344 |
| Passive real-input takeover, timer handoff, drift/edges, four window states, persistence/lifecycle | 93/93 |
| Native docking/catch centering | 587/587 |
| Canonical UI/fullscreen rendered desktop | 519/519 |
| Canonical UI rendered mobile | 574/574 |
| Mobile harness | 162/162 |
| Mobile presentation | 252/252 |
| HUD/camera parity | 53/53 |
| Morning stability | 205/205 |
| Native lifecycle | 1832/1832 |
| Mobile lifecycle | 1052/1052 |
| Interaction | 93/93 |
| Developer Playtest | 90/90 |
| Full fishing regression | 22950/22950 |

Full session regression includes Fight 24/24, Presentation 10/10, Bite Timing 14/14, Stability 27/27, Fresh Save 55/55, Triple Triad backend 101/101, crafting 14/14 with 36 combinations, and Card Maker 10/10. Economy remains the existing **22/24** provisional balance guardrails, unchanged.

Permanent journey coverage moves a physical disabled-in-fixture bait, not its sprite, through both edges and every intermediate safe position using real cast/return callbacks. Each safe traversal asserts the exact camera transform for 60 frames. Passive coverage uses a viewport input witness plus normal reel state to prove one forwarded K and valid release, and checks same bait/session IDs plus unchanged activity-independent window state/width.

Superseded 864px world/crop and interior hysteresis expectations were corrected to the explicitly requested contract. No transaction or fishing checks were removed. The stricter deck bounds fixture now parents its disposable editor under the same Triple Triad CanvasLayer as production, rather than directly under the 480px world viewport.

The first browser result was excluded: inspection found an old QA server serving the previous build on 8077. The current fixture was exported under `surface43.html`, served from the verified new directory, and rerun. Current browser console: `PORTRAIT FISHING ACCEPTANCE: {"casts":3,"failures":[],"passed":1344,"renderer":"web","total":1344}` from `/surface43.js`, 2026-10-10 06:06:12 UTC. Temporary browser tab, viewport override and localhost QA server were cleaned up. Production HTTPS 8060 was not restarted.

Existing GLES `_save_to_cache` filesystem diagnostics and Web current-field resource UID/text-path fallback warnings remain; they are not newly suppressed. Final project scripts had no parse/freed-instance errors. Initial sandbox runs without userdata write access were discarded and rerun with isolated writable QA saves. Final logs are in ignored `build/mobile-web/canonical43-audit/` and `build/mobile-web/canonical43-final/`.

## Commands actually executed

Godot executable: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`.
Each native command used `--path . --rendering-method gl_compatibility --script res://scripts/qa/<script>.gd`, with these additional arguments:

| Script | Additional arguments |
|---|---|
| fishing_fight_camera_tracking_qa | --headless; also --headless -- --mobile |
| portrait_fishing_acceptance_runner | -- --edge-pan; also -- --companion --edge-pan |
| passive_fishing_qa | none |
| desktop_companion_docking_qa | none |
| canonical_portrait_surface_qa | -- --rendered; also -- --mobile --rendered |
| mobile_portrait_harness_qa | none |
| mobile_presentation_standard_qa | none |
| mobile_gameplay_parity_qa | none; also -- --rendered --capture-dir=res://build/canonical43/rendered |
| morning_stability_qa | none |
| runtime_lifecycle_qa | --headless; also --headless -- --mobile |
| world_interaction_qa | --headless |
| developer_playtest_qa | none |
| session_contract_runner | --headless |

The temporary Linux Web fixture used the same export preset with the QA main scene isolated in the mirror; its production main-scene setting was restored in finally. Production rebuild command: `& tools/mobile/build_mobile_playtest.ps1`. Final `git diff --check`: PASS.

## Web release and physical acceptance

Final Linux/WSL production build: **32,254,512-byte index.pck**, **9,970-byte project.binary**, valid **ECFG** header. Same index basename and normal mobile main scene. HTTPS unchanged; refresh the existing Safari address.

Rendered native/browser tests are complete; physical iPhone/Safari acceptance is still required. Check: full uncropped wider world; no yaw anywhere inside the safe rectangle, slow pan only past each edge; hard-left/right retrieve and catch dismissal keep their approved return; dialogue/catch placement; tall menu gutter scrolling; Passive K immediately reels/hooks without a second press; timer-ready takeover including collapse without geometry changes. Ordinary desktop Triple Triad is uniformly fitted to the shorter canvas and warrants a readability check.

## Complete changed-file manifest

- `export/index.html`
- `export/index.pck`
- `project.godot`
- `scripts/camera_rig.gd`
- `scripts/desktop/desktop_companion.gd`
- `scripts/fishing_fight_camera_tracking.gd`
- `scripts/gameplay/passive_fishing_controller.gd`
- `scripts/mobile/mobile_portrait_harness.gd`
- `scripts/mobile/responsive_menu_surface.gd`
- `scripts/qa/canonical_portrait_surface_qa.gd`
- `scripts/qa/desktop_companion_docking_qa.gd`
- `scripts/qa/fishing_fight_camera_tracking_qa.gd`
- `scripts/qa/mobile_portrait_harness_qa.gd`
- `scripts/qa/mobile_presentation_standard_qa.gd`
- `scripts/qa/morning_stability_qa.gd`
- `scripts/qa/passive_fishing_qa.gd`
- `scripts/qa/portrait_fishing_acceptance.gd`
- `scripts/triple_triad/triple_triad_game.gd`
- `scripts/ui/canonical_game_surface.gd`
- `scripts/ui/portrait_ui.gd`
- `docs/qa/canonical_43_passive_take_control_v1.md`
