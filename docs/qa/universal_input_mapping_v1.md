# Universal Input Mapping & Desktop Controls v1

Implemented 2026-10-12 against the existing dirty desktop v1/v2 work. No camera, caster, bait physics, HUD, card rules, progression, prices, game-save schema or native AppBar implementation changed.

## Audit and final defaults

| Intent | Keyboard | Touch | Existing semantic actions |
| --- | --- | --- | --- |
| Up | W | Stick up | move_forward / ui_up |
| Left | A | Stick left | move_left / ds_left / ui_left |
| Down | S | Stick down | move_back / ui_down |
| Right | D | Stick right | move_right / ds_right / ui_right |
| Primary / confirm / cast / reel | K | A | enter_fishing |
| Back | I | B | cancel_fishing |
| Main menu / deck details | J | Y | main_menu |
| Card/context interaction | C | X | world_card_challenge |
| Left shoulder | Q | L | cam_right / shoulder_left |
| Right shoulder | E | R | cam_left / shoulder_right |
| Lure menu / deck save | L | Existing Equip route | lure_menu |

Q originally maps to the action called `cam_right`, and E to `cam_left`. Their actual camera/page behavior is preserved rather than reversing camera controls to match the names. Q/E also page through menus and E rotates cards in its existing context. A/D already share movement and fishing steering. The new preference groups make these intentional context aliases explicit.

L is a separate lure-menu shortcut and also saves a deck in the existing deck setup context. Mobile X remains card/context interaction, never a new L shortcut. R retains fixed card rotation/deletion commands; T retains a fixed debug crafting command. R/T and non-letter keys are therefore unavailable as new customizable bindings. Enter/Escape/arrows/PageUp/PageDown/numeric deck profiles/function/debug keys retain their existing fixed uses. Arbitrary sharing between different intent groups is rejected.

Start remains Space for manual pause/resume, with the existing mobile deck-start use. Desktop deck start also retains Enter. The visible Select control toggles equipment; the older `BUTTON_KEYS.SELECT=F10` constant is not that visible button's current route. No new Start/Select keyboard defaults were invented. A future gamepad layout remains a separate design decision; existing non-key InputMap events are preserved and hosts forward semantic/joypad events.

## Authority and persistence

`InputBindings` is one autoload using `UniversalInput`. InputMap remains the runtime matching/polling authority. The service owns keyboard preference choices, approved aliases and temporary capture state, not gameplay commands. Controllers retain all interaction, fishing, modal and match ownership.

Existing private key helpers now consult semantic InputMap actions through a small compatibility helper. Their KEY arguments denote the old intent, not the actual current physical key. This avoids rewriting unrelated controller state machines. Touch and desktop clicks resolve their intent to the current bound key and send one balanced event through the existing host forwarding route. Mobile X retains its existing named card-action route. Movement touch strengths remain analog; rebinding releases old held generations.

Preferences use `user://input_bindings.json`, version 1, independently of game saves. They contain one physical letter key per intent group. Startup validates the complete resulting map before applying it. Missing fields receive validated defaults, unknown fields do not create actions, and conflicting/invalid/future-version payloads are rejected. Invalid current files recover from a validated `.bak` or defaults with a warning.

Writes serialize to `.tmp`, flush and validate, move the previous valid file to `.bak`, then rename the validated temporary file into place. A failed commit preserves the active mapping and displays an error. A corrupt current file does not replace a good backup. This is practical file-level atomic recovery, not a claim of power-loss-proof disk transactions. Game-save paths/schema are untouched.

Keyboard edits retain live non-key InputMap events and fixed directional UI arrows. They do not keep a second stale cache of those events. World interaction press claims clear when mappings change. Capture has a weak UI owner, cancels when the owner closes/dies, and blocks the captured key until release. It clears polling state as well as consuming dispatch. Held touch/stick and desktop-button sources release on capture, rebind, focus loss or teardown. Captured keys cannot reach cast/card/menu/window hotkey handlers.

## Settings and desktop UI

The existing Options page now hosts a single scrollable Controls editor in the shared responsive menu surface. That surface previously masked authored Options children; merely adding an editor to the old panel would leave it invisible. Rows show current keys, mouse/touch can choose a row, keyboard navigation works, and capture displays waiting/conflict/save status. Conflicts remain pending until the player chooses a different eligible key or cancels. Defaults persist; failed writes report failure without changing active keys.

Real pointer validation also exposed viewport ownership: the overlay viewport renders the menu, while GUI input belongs to the gameplay viewport. A scoped Controls-page pointer bridge maps display coordinates to that GUI owner before underlying shell widgets can steal a click. Original touch is emulated once; the root's duplicate mouse-emulation event is consumed. Touch scrolling cancels the pending row click and scrolls the native list, so dragging cannot start rebinding. The existing outer menu gutter still pans the clipped menu surface. Other menu layouts are unchanged.

The compact reusable desktop controls provide I/J/K/C/Q/E equivalents, display live configured keys and support held reeling. Root event forwarding occurs once; no direct cast/reel/card commands are called by the widgets. Direct Dock Left, Dock Right and Float/Undock appear at the far right of the environmental strip. Narrow desktop uses a compact vertical window-control column; the existing environmental category order remains intact. Active/Passive and collapse stay accessible. World aspect selection, toolbar height budgets and AppBar geometry remain unchanged; only compact control placement/width changed.

Explicit desktop action captions in the shared menu presenter resolve current keys; mobile captions retain logical touch labels. Baked help art and dedicated fixed utility shortcuts were not redesigned.

## Verification actually run

Godot executable: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`.

Existing isolated wrappers supply `--headless --path <project>` (`run.py`) or `--rendering-method gl_compatibility --path <project>` (`render_run.py`), with logs under `build/mobile-web/root-repair`. Native window fixtures ran outside the sandbox with approval.

| Command suffix | Result |
| --- | --- |
| `--editor --import --quit` | Exit 0; no script errors in final import log |
| `--script res://scripts/qa/universal_input_qa.gd` (Compatibility rendered) | 148/148 |
| Same dedicated fixture, headless | 144/148; four pointer/window-layout checks fail in the dummy backend; not counted as green |
| `--script res://scripts/qa/session_contract_runner.gd` | Full fishing 22950/22950; Triple Triad 101/101; contract PASS; zero orphans |
| `--script res://scripts/qa/seaside_shell_layout_qa.gd` | 88/88 |
| `--script res://scripts/qa/mobile_landscape_shell_qa.gd` | 455/455 |
| `--script res://scripts/qa/runtime_lifecycle_qa.gd` | 1832/1832 |
| `--script res://scripts/qa/runtime_lifecycle_qa.gd -- --mobile` | 1052/1052 |
| `--script res://scripts/qa/empty_lure_retrieval_qa.gd` | Isolated rerun 286/286; earlier concurrent run 285/286 on `authored action/current contributors cannot reverse active retrieval` |
| `--script res://scripts/qa/fishing_camera_reconstruction_qa.gd` | 124/124 |
| `--script res://scripts/qa/fishing_camera_hud_stability_qa.gd -- --desktop` (rendered) | 45/45 |
| `--script res://scripts/qa/passive_fishing_qa.gd` | 95/95 |
| `--script res://scripts/qa/desktop_companion_docking_qa.gd` (native/rendered) | 657/657 |
| `--script res://scripts/qa/desktop_floating_qa.gd` (native/rendered) | 14/14 |
| `--script res://scripts/qa/mobile_gameplay_parity_qa.gd` | 49/53, same four baseline foot-Y failures |
| `git diff --check` | PASS |

The dedicated fixture exercises all default/custom groups and aliases, old-key rejection, repeated writes/reloads, validated backup recovery, duplicate/outdated payloads, commit failure, conflict capture, owner close, captured polling-state clearance, semantic card-controller input, actual desktop mouse capture, virtual remapped casting/held retrieval, and actual portrait/landscape touch capture/cancel/scroll/reset. It also proves that keyboard edits preserve a live joypad binding. No configured controller scheme or physical iPhone acceptance is claimed.

Intermediate masking, pointer ownership and indentation failures were corrected; those runs are not reported as passes. Headless GUI misses are explicitly retained above. The isolated empty-lure rerun passed, but the earlier intermittent current/action assertion is not conclusively classified as a baseline defect; its cause remains a separate uncertainty. No fishing physics or assertions were changed to remove it. Existing GLES shader-cache write diagnostics and known H12 balance alerts remain visible.

Rendered captures inspected:

- `build/mobile-web/input-qa/settings-desktop.png`
- `build/mobile-web/input-qa/desktop-controls-fishing.png`
- `build/mobile-web/input-qa/settings-mobile-390x844.png`
- `build/mobile-web/input-qa/settings-mobile-932x430.png`
- Native docking captures remain under `build/desktop-docking/`.

## Web delivery

Ran `.\tools\mobile\build_mobile_playtest.ps1` using the existing Linux/WSL Godot 4.7.2 workflow. Exit 0. Published `export/index.html` and matching index JS/WASM/PCK. Validated PCK: **32,632,584 bytes**; `project.binary`: **10,048 bytes**, **ECFG** header. Refresh Safari at the existing HTTPS address. The server/certificates were not changed or restarted. This validates export integrity; physical Safari acceptance still needs testing.

## Exact files changed for this pass

- `project.godot`
- `scripts/input/universal_input.gd` and generated `.uid` (new)
- `scripts/input/controls_settings.gd` and generated `.uid` (new)
- `scripts/input/desktop_action_controls.gd` and generated `.uid` (new)
- `scripts/qa/universal_input_qa.gd` and generated `.uid` (new)
- `scripts/fishing_menu.gd`
- `scripts/fishing_economy_menu.gd`
- `scripts/fishing_debug_menu.gd`
- `scripts/beach_crafter_npc.gd`
- `scripts/beach_crafting_menu.gd`
- `scripts/beach_gathering_node_3d.gd`
- `scripts/beach_merchant_npc.gd`
- `scripts/dialogue/dialogue_controller.gd`
- `scripts/economy/fishing_card_maker_menu.gd`
- `scripts/economy/fishing_card_maker_npc.gd`
- `scripts/mastery/fishing_master_lesson_npc_base.gd`
- `scripts/mastery/fishing_master_still_water_npc.gd`
- `scripts/progression/fishing_reward_claim_npc_base.gd`
- `scripts/triple_triad/triple_triad_campaign_qa_menu.gd`
- `scripts/triple_triad/triple_triad_competition_interaction_3d.gd`
- `scripts/triple_triad/triple_triad_debug_menu.gd`
- `scripts/triple_triad/triple_triad_deck_setup.gd`
- `scripts/triple_triad/triple_triad_harbor_request_board.gd`
- `scripts/triple_triad/triple_triad_input_controller.gd`
- `scripts/triple_triad/triple_triad_reward_view.gd`
- `scripts/triple_triad/triple_triad_world_reward_trigger.gd`
- `scripts/triple_triad/triple_triad_world_reward_trigger_3d.gd`
- `scripts/world/location_travel_point.gd`
- `scripts/world/manillo_trader_npc.gd`
- `scripts/world_interaction_router.gd`
- `scripts/npc/npc_catalogue_preview.gd`
- `scripts/desktop/desktop_companion.gd`
- `scripts/mobile/mobile_portrait_harness.gd`
- `scripts/mobile/mobile_touch_controls.gd`
- `scripts/mobile/responsive_menu_surface.gd`
- `scripts/ui/portrait_ui.gd`
- `scripts/ui/seaside_shell_actions.gd`
- `scripts/ui/seaside_shell_layout.gd`
- `scripts/ui/seaside_shell_view.gd`
- `docs/qa/universal_input_mapping_v1.md` (new)
- Generated Web output in `export/` (ignored build artifacts).

Previously dirty desktop v1/v2 reports, dashboard, QA, environment-strip and Windows helper files were preserved. The broad-looking controller inventory above consists of input-boundary migrations, not warning cleanup or state-machine refactors. All original filenames remain.
