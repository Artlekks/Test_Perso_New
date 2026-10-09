# Desktop Companion Foundation v1

## Launch

From the project directory in PowerShell:

```powershell
& .\tools\desktop\run_portrait.ps1 -Companion
```

The helper uses the installed Godot 4.7.2 executable and explicitly opens
`res://actors/desktop/DesktopCompanion.tscn`. Ordinary desktop portrait and
fullscreen remain available:

```powershell
& .\tools\desktop\run_portrait.ps1
& .\tools\desktop\run_portrait.ps1 -Fullscreen
```

Companion and Fullscreen are separate modes; the helper rejects combining them.

## One session, three display modes

DesktopCompanion is a presentation host, not a gameplay controller. Its single
SubViewport holds the ordinary world scene and the same 640 × 864 composition.
GameplaySceneRoot's existing host interface handles scene resolution and travel.
Session CanvasLayers join that viewport and return to their original owners when
the host exits. There are no mobile touch controls or parallel menu controllers.

Click **Mode** or press **Ctrl+Shift+F12** while Active to cycle modes:

| Mode | Display | Default window footprint |
|---|---|---:|
| Active | Full portrait, normal keyboard gameplay | 480 × 676, including 28px developer bar |
| Passive | Smaller uniformly fitted preview | 240 × 220 |
| Collapsed | Minimal status and Mode control, game image hidden | 96 × 160 |

Passive/Collapsed windows do not acquire keyboard focus. Restore with the Mode
button; Active reacquires focus. Keyboard forwarding is Active-only. Contextual
shared UI selects keyboard hints (K/I/ENTER), not mobile A/B/START hints.

Mode changes only alter window size/position, focusability, display visibility
and a status label. They do not touch SceneTree.paused, process modes, fish
animation, saves, progression, services or the physical bait. The game viewport
continues updating/rendering even when its texture is hidden, ensuring existing
animation and timer behavior remains intact. Reduced rendering cost is deferred
until it can be verified without suspending gameplay callbacks.

Normal fishing continues underneath Passive/Collapsed, including ordinary bite
timing. No passive fishing simulation, unattended guarantees or notifications
have been implemented.

## Centralized sizing and placement

Tune `scripts/desktop/desktop_companion.gd` exports:

- `active_scale` (0.75)
- `passive_size` (240 × 220)
- `collapsed_size` (96 × 160)
- `gameplay_scene`

`SURFACE` (640 × 864) and `CHROME_HEIGHT` (28) are centralized constants.
Active scale is bounded by the current monitor's usable width/height. Each mode
is positioned against that monitor's right edge and centered vertically using
DisplayServer.screen_get_usable_rect. No actual monitor resolution is assumed;
headless fixtures fall back to the canonical surface size.

## Verified foundation

Rendered companion fishing acceptance passes **91/91**. Three casts complete
through actual animation callbacks. Each waterborne cast cycles through
Passive/Collapsed/Active while asserting:

- identical session and physical bait instance IDs;
- fishing still processes and the tree is not unexpectedly paused;
- canonical viewport remains 640 × 864.

After restoring Active, inventory, crafting and Card Maker menus open/close
through their original controllers. A Developer Mode card encounter starts a
match and closes normally. Keyboard hints and absence of touch controls are
asserted. These checks validate state preservation, not final companion chrome
or a future passive-fishing design.

Run the rendered fixture with:

```powershell
$qaGodot = "$env:USERPROFILE\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe"
& $qaGodot --path . --rendering-method gl_compatibility --script scripts/qa/portrait_fishing_acceptance_runner.gd -- --companion
```

The ordinary desktop/fullscreen canonical UI check passes **521/521**, including
an actual fullscreen window. On wide monitors, external pillarboxing remains
intentional and the game uses the same portrait composition.

For all stabilization file changes, commands, QA counts, known environmental
diagnostics and physical phone acceptance limitations, see
`docs/ui/canonical_portrait_stabilization_v1_1.md`.

Future hooks deliberately excluded: Pomodoro scheduling, passive fishing rules,
OS notifications, productivity rewards, polished window chrome and shell-specific
gameplay/UI controllers.
