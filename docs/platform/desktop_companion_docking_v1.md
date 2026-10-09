# Desktop Companion Docking v1 + Mobile HUD State Repair v1

## Launch and controls

```powershell
& .\tools\desktop\run_portrait.ps1 -Companion
```

Click **Dock Right** to reserve the right edge of the window's monitor. Click
**Float** to release the reservation and restore the previous floating rectangle.
**Mode** / Ctrl+Shift+F12 retains Active → Passive → Collapsed cycling. Restore
Active with Mode before clicking Float when Collapsed. No game/session reload.

## Native implementation

`CompanionWindowPlatform` isolates command/status IPC and process lifetime from
the game. On Windows it launches `tools/desktop/windows_appbar.py` using Python's
standard-library ctypes. The current project's installed Python is reused; an
explicit interpreter can be supplied with `run_portrait.ps1 -Companion
-PythonPath 'C:\path\python.exe'` or `FISHING_COMPANION_PYTHON`. No packages install.

The helper owns one transparent, non-activating tool HWND with a Windows message
pump. It negotiates an actual Shell AppBar using ABM_NEW, ABM_QUERYPOS and
ABM_SETPOS; ABM_REMOVE releases it. It positions the borderless Godot companion
inside that strip. It does not use SPI_SETWORKAREA or merely always_on_top.
The transparent reservation spans the usable monitor height; the existing
portrait window remains vertically centered within it. Space above/below the
portrait belongs to the reserved strip, so applications cannot use that space.

Shell work-area integration follows Microsoft's
[Application Desktop Toolbars API](https://learn.microsoft.com/en-us/windows/win32/shell/application-desktop-toolbars).

IPC uses atomic JSON files in a per-game-PID cache directory, containing only
native window geometry/ownership. `FISHING_COMPANION_IPC` lets QA use a disposable
workspace directory. The helper remains alive through Undock so it can be reused.
The host polls status at 10Hz and surfaces startup/helper failures in the Dock
button tooltip, returning to floating presentation. Cached IPC files are small
diagnostic artifacts, not gameplay saves or new service instances.

## Width, monitor and DPI policy

Central exports on `DesktopCompanion`:

| Mode | Reserved width, physical Windows pixels | Default portrait window |
|---|---:|---:|
| Active | `dock_active_width = 480` | 480 × 718 |
| Passive | `dock_passive_width = 240` | 240 × 220 |
| Collapsed | `dock_collapsed_width = 96` | 96 × 160 |

Active height = width × 864 / 640 + 28px chrome + 42px keyboard strip. The
canonical SubViewport always remains 640 × 864. A small monitor can limit the
outer window height; the image remains uniformly fitted, not stretched.

MonitorFromWindow selects the companion's current monitor. GetMonitorInfo and
Shell negotiation respect the taskbar/other AppBars, including nonzero monitor
origins. The sidecar uses per-monitor-v2 DPI awareness and physical pixels rather
than assuming a resolution or converting by a guessed scale. Move the floating
window onto another monitor, then Dock Right. Shell position/display/DPI
notifications trigger re-negotiation. Mixed-DPI/multiple physical monitors still
need manual acceptance on a machine with those configurations.

## Cleanup

Undock requests ABM_REMOVE first, then restores floating geometry after the Shell
acknowledges release. Restoring before acknowledgment was found to let Windows
clamp the window against the old reservation; that ordering is now tested.

Normal host teardown sends `close`; the helper runs ABM_REMOVE in finally and
destroys its HWND. It independently watches the game's native process handle,
so terminating/crashing Godot also removes the reservation. It does not rewrite
the global desktop work rectangle, which avoids leaving a permanent narrowed
desktop setting. Forced helper/Explorer termination and system shutdown remain
OS-managed HWND/Shell lifetime cases, not a promised persistent restoration agent.

## Keyboard reminder

An unobtrusive, read-only 42px bottom shell label is visible in Active. It is
outside the canonical game surface. Fishing, exploration and modal/dialogue
contexts choose relevant reminders. Action-backed keys resolve from live
InputMap events (movement, camera rotation, fishing, lure and card challenge).
The current legacy dialogue/menu handlers consume literal K/Enter, I/Esc, W/S
and J, so those reminders explicitly reflect the actual raw-key controllers;
they are not advertised as remappable actions. No touch A/B/C controls are added
to desktop. Optional keycap-depression feedback is not implemented.

## Mobile dialogue defect and repair

The prior stabilization shell cached DialogueView as a scrollable surface owner.
`_process()` switched `_surface_scroll` from the bottom world crop to zero as soon
as dialogue became visible, shifting the whole world, HUD and canonical image.
Closing dialogue switched crop ownership again; there is no dialogue HUD-hide
call in the HUD/controller chain. The apparent HUD disappearance is clipping
from shell placement, not deleted HUD nodes or a camera reset.

DialogueView is now excluded from surface-scroll ownership both during discovery
and during modal evaluation. Its existing bottom-anchored panel overlays the
unchanged world. Menus and catch results retain their approved top/scroll policy.
No camera, HUD tween, canonical canvas, touch mapping, marker or splash changes.

Rendered fixture opens actual Card Maker, Merchant, Crafter and Still Water
Master interaction entry points and a generic DialogueNPCBridge, four cycles each.
It closes each through the mobile B adapter. Camera transform, image/display
rectangles, safe area, viewport size, scroll offset, touch geometry and exploration
HUD visibility/rectangles/modulate must match before/during/after. Pause ownership
must release on exit. Entry methods isolate the overlay audit from range/facing;
existing interaction/input QA independently checks routing and touch mappings.

## Platform boundary

Non-Windows hosts disable Dock Right. No speculative macOS docking implementation.
A future macOS adapter must provide window placement and cleanup semantics behind
the same boundary and establish whether the OS supports reserving work area for
ordinary applications. A floating macOS panel alone would not meet this contract.
No Win32 calls are added to fishing, session composition or UI controllers.

## Verification

Native maximization uses a disposable ordinary WS_OVERLAPPEDWINDOW
created by `verify_companion_docking.py`, not changes to the user's applications.
Physical iPhone acceptance is still needed; Chromium Web rendering is not Safari.

Measured native monitor: 2560 × 1600, taskbar work area `[0,0,2560,1528]`.
Active shrank it to `[0,0,2080,1528]`; Passive to `[0,0,2320,1528]`; Collapsed to
`[0,0,2464,1528]`. The ordinary maximized witness's client right edge was exactly
2080 while Active. Undock, normal docked close and forced game termination all
restored `[0,0,2560,1528]`. The same session/game instance and camera survived modes.

| Check | Final measured result |
|---|---:|
| Native AppBar/modes/InputMap/Undock fixture | 33/33 |
| Maximized ordinary window + forced exit + normal close witness | 3/3 |
| Rendered native dialogue, 20 open/close cycles | 540/540 |
| Rendered Web dialogue at 390 × 664, 20 cycles | 540/540 |
| Mobile harness | 162/162 |
| Mobile presentation | 252/252 |
| Rendered canonical mobile / desktop (includes TT/fullscreen) | 574/574 / 521/521 |
| Rendered layout | 44/44 |
| Rendered mobile / companion fishing, three casts each | 47/47 / 91/91 |
| Dialogue readability / dialogue system | 125/125 / 175/175 |
| World interaction | 93/93 |
| Session composition, 12 alternating hosts | 102/102 |
| Native / mobile lifecycle, six travel cycles each | 1832/1832 / 1052/1052 |
| Fight camera | 164/164 |
| Full fishing regression | 22950/22950, orphan nodes 0 |
| Triple Triad | 101/101 |
| Developer Mode | 90/90 |
| Godot final import / Python compile / git diff --check | PASS |

All final native suites exited successfully and had no GDScript errors. Existing
GLES shader-cache write diagnostics remain in rendered runs. Economy balance
remains truthfully 22/24; no balance data/guardrails changed.

Commands use the installed `Godot_v4.7.2-stable_win64.exe`, `--path .` and
`--rendering-method gl_compatibility`. Script suites:

```text
--script res://scripts/qa/desktop_companion_docking_qa.gd
res://actors/mobile/MobileDialogueStateQA.tscn
--script res://scripts/qa/mobile_portrait_harness_qa.gd
--script res://scripts/qa/mobile_presentation_standard_qa.gd
--script res://scripts/qa/dialogue_readability_qa.gd -- --rendered --capture-dir=<disposable directory>
--script res://scripts/qa/canonical_portrait_surface_qa.gd -- --rendered --mobile
--script res://scripts/qa/canonical_portrait_surface_qa.gd -- --rendered
--script res://scripts/qa/mobile_portrait_layout_qa.gd
--script res://scripts/qa/portrait_fishing_acceptance_runner.gd
--script res://scripts/qa/portrait_fishing_acceptance_runner.gd -- --companion
--headless --script res://scripts/qa/world_interaction_qa.gd
--headless --script res://scripts/qa/session_composition_separation_qa.gd
--headless --script res://scripts/qa/runtime_lifecycle_qa.gd
--headless --script res://scripts/qa/runtime_lifecycle_qa.gd -- --mobile
--headless --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd
--headless --script res://scripts/qa/session_contract_runner.gd
--headless --script res://scripts/qa/developer_playtest_qa.gd
--headless --editor --import --quit
python tools/desktop/verify_companion_docking.py --godot <installed Godot executable>
python -m py_compile tools/desktop/windows_appbar.py tools/desktop/verify_companion_docking.py
git diff --check
```

Web diagnosis used a disposable Linux export with only its mirrored main scene
temporarily changed to MobileDialogueStateQA and then restored, served over
loopback port 8077. Browser viewport explicitly set to 390 × 664; console report
540/540 with no script errors. The temporary browser tab/server were removed.
The shipped export uses the normal MobilePortraitHarness, not the QA fixture.

Final publication command:

```powershell
& .\tools\mobile\build_mobile_playtest.ps1
```

Linux/WSL export succeeded: index.pck 32,200,424 bytes; project.binary 9,887 bytes,
ECFG header. Normal export/index.html is ready for Safari refresh. The original
HTTPS listener remained `0.0.0.0:8060`, PID 18464, and was not restarted.

## Files changed in this pass

- `.gitignore` (disposable native QA/cache artifacts)
- `scripts/mobile/mobile_portrait_harness.gd`
- `scripts/desktop/desktop_companion.gd`
- `scripts/desktop/companion_window_platform.gd` and its `.uid`
- `scripts/desktop/companion_keyboard_strip.gd` and its `.uid`
- `tools/desktop/windows_appbar.py`
- `tools/desktop/verify_companion_docking.py`
- `tools/desktop/run_portrait.ps1`
- `scripts/qa/desktop_companion_docking_qa.gd` and its `.uid`
- `scripts/qa/mobile_dialogue_state_fixture.gd` and its `.uid`
- `actors/mobile/MobileDialogueStateQA.tscn`
- `docs/platform/desktop_companion_foundation_v1.md`
- `docs/platform/desktop_companion_docking_v1.md`
- `export/index.html`
- `export/index.pck`

Manual acceptance: refresh Safari, repeatedly talk/Back with the five NPC
families; the world/HUD must remain in place. On Windows launch Companion, dock,
maximize your usual app, cycle modes, float and close. Repeat after moving the
floating companion to each monitor, especially different DPI/taskbar setups.
