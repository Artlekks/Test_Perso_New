# Fishing safe rectangle and Windows Floating restoration

## Scope

This pass changes fishing-camera containment/debug visualization and Floating window ownership only. Shell layout rectangles, mobile styling/input, menu proportions, Dock Left/Right negotiation and the collapse/minimize implementation are unchanged. No bait/fish movement, economy, cards, crafting or Passive scheduling code changed.

## Fishing root cause and implementation

The previous solver only searched a yaw orbit. A vertically unsafe target near horizontal center could leave `PanState.HOLD`; yaw also cannot guarantee vertical clearance, and the ±55° cap can make a horizontal shot infeasible. There was no post-correction two-axis invariant or visible guide tied to the actual thresholds.

The single authority remains the exported `fight_safe_left/right/top/bottom` fields in `scripts/camera_rig.gd`, exposed through `fishing_safe_region()` and `fishing_safe_region_pixels()`:

| Edge | Ratio | Canonical pixel |
| --- | --- | --- |
| Left | 0.18 | 115.2 |
| Right | 0.82 | 524.8 |
| Top | 0.22 | 105.6 |
| Bottom | 0.70 | 336.0 |

No threshold was aesthetically tuned. The shared getter feeds the yaw solver, residual framing correction, debug rendering and QA assertions; chrome and touch controls do not participate in these calculations.

- Horizontal: the existing slow exponential yaw response and ±55° cap remain. Any remaining horizontal screen error is corrected with the minimum `Camera3D.h_offset` change needed to reach the nearest boundary. This is necessary for the hard containment contract when a slow or saturated yaw orbit alone cannot contain the target immediately.
- Vertical: a bounded numerical solve applies the minimum local camera pitch correction needed to reach the top/bottom boundary. It does not translate the camera downward into terrain. Pitch alters perspective depth, so any remaining horizontal error is resolved afterward.
- Across the optical plane: only if needed, the camera retreats along its existing unpitched orbit axis enough to regain a positive projection depth; the bait is never moved. This avoids singular or mirrored projections. It is not a distance/framing redesign during ordinary safe play.
- Inside: yaw, pitch and optical offsets hold. There is no neutral-return spring while water tracking owns the camera. Only retrieve/result dismissal/exploration restoration releases that pose through the existing return owner.
- Return: the existing exponential return response also unwinds any residual pitch/framing correction to the captured post-aim pose. It does not add a second tween/controller or change the established return speed.

The nearest-edge correction prioritizes containment over preserving the exact optical player pixel when a target is outside the legal region. The base shot, FOV and physical player/bait positions remain unchanged. Vertical pitch changes only when required by a top/bottom violation.

## Yellow guide and firewall

`scripts/ui/fishing_safe_region_debug.gd` is a scene-owned, mouse-ignoring Control in CameraRig's CanvasLayer 4. In debug builds it draws the authoritative pixel rectangle with a yellow, unfilled, non-antialiased **3 logical px** outline during water/fight tracking. It is composed inside the canonical world viewport, below important modal layers. `fishing_safe_debug_visible` defaults to true and remains enabled pending physical approval.

After correction, the active camera projects the unchanged physical `active_bait` target. A violation beyond **0.5 logical px** lasting **0.10 seconds** increments `safe_containment_failures` and emits a debug `push_error` with the target, projected point, legal rectangle and yaw. The solver's tiny normalized numerical tolerance only prevents floating-point boundary jitter; it does not move the authored bounds.

The deliberate negative test `--prove-firewall` feeds a below-screen projection, expects a visible `FISHING SAFE REGION VIOLATION`, and exits **1**. That failure is intentional and reported separately from successful journeys.

## Floating root cause and implementation

The shell's maximize action entered `MODE_FULLSCREEN`, removing the ordinary Windows title bar and native maximize/drag-restore behavior. The native AppBar sidecar also accepted work-area notifications while Floating and left its dirty flag set; a release command could consequently be replayed, including a persisted restore rectangle.

Floating now uses normal `MODE_MAXIMIZED`/`MODE_WINDOWED`, enables native decoration/resizing after the AppBar acknowledgement, clears tool-window/non-activating extended styles on release, and performs the native frame-style refresh once. Floating work-area notifications do not start a geometry loop. The helper remains idle until another explicit ownership command.

Dock registration/negotiation and the widget/collapse branch are unchanged. The maximized-to-dock adapter merely restores windowed mode before the existing dock command. No gameplay/session recreation occurs.

Native witness evidence: style **0x16cf0000**, extended style **0x40110**, native title-bar `HTCAPTION`, bottom-right corner `HTBOTTOMRIGHT`; no AppBar reservation while Floating. Manual halves remained **[0,0,1280,1528]** and **[1280,0,2560,1528]**, and a separate disposable ordinary window occupied the other half without a geometry writer moving either window. Native maximize/restore passed. The user reported: **“the floating is working so far.”** Native hit-testing and manual placement do not independently prove every Windows Snap shared-divider gesture.

## QA commands and results

Godot: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`.

Headless script command: `& <Godot> --headless --path . --script res://scripts/qa/<script>`, with the arguments below. Rendered commands replace `--headless` with `--rendering-method gl_compatibility`. Saves are isolated.

| Test | Arguments/execution | Result |
| --- | --- | --- |
| `fishing_fight_camera_tracking_qa.gd` | Headless; includes vertical-only/corner retrieve | 205/205 |
| `fishing_safe_rectangle_qa.tscn` | Scene argument instead of `--script`; desktop headless | 942/942 |
| `fishing_safe_rectangle_qa.tscn` | Headless, `-- --mobile` | 942/942 |
| `fishing_safe_rectangle_qa.tscn` | Rendered, `-- --rendered` | 950/950 |
| `fishing_safe_rectangle_qa.tscn` | Rendered, `-- --mobile --rendered` | 950/950 |
| `fishing_safe_rectangle_qa.tscn` | `-- --prove-firewall` | Expected violation and exit 1 |
| `passive_fishing_qa.gd` | Real Passive lease and opposite-edge/inside-hold journey | 95/95, headless and rendered |
| `desktop_companion_docking_qa.gd` | Rendered native, including collapse | 587/587 |
| `desktop_floating_qa.gd` | Rendered, via witness `-- --witness` | 15/15 |
| `tools/desktop/verify_companion_floating.py` | Bundled Python; optional `--godot` | 13/13 native checks |
| `seaside_shell_layout_qa.gd` | Rendered, ordinary-maximize expectation | 91/91 |
| `runtime_lifecycle_qa.gd` | Headless desktop/mobile | 1832/1832 desktop; 1052/1052 mobile |
| `session_contract_runner.gd` | Headless full fishing | 22950/22950; session contract PASS; orphan nodes 0 |
| Web safe-rectangle journey | Rendered browser, two repeated mobile journeys | 630/630; all eight edge/corner cases twice; no script errors or containment violations |
| `git diff --check` | Git | PASS |

The journeys enter fishing and cast through real production animation/callback paths using a disposable Passive orchestrator. They sample real current/Passive frames, then inject deterministic physical endpoints with fixture simulation frozen to exercise every edge and corner. They compare the physical bait before/after correction, assert projected center containment/HUD clearance, test central hold, and retrieve/recast repeatedly with the same session. Native rendered journeys also inspect the actual yellow pixel at the canonical 18%/22% corner; mobile captures cover portrait and landscape. Extreme injected endpoints can lie outside authored terrain and are containment fixtures, not an aesthetic acceptance claim.

Three prior expectations required correction: exact player optical framing during an unsafe target, yaw-only saturation remaining uncontained, and a Passive latch continuing to track after reentry. Those contradict this pass's hard containment/immediate-hold contract. New tests retain physical-position, base-distance/FOV, central-hold, capped-yaw and restoration assertions. The shell maximize assertion now expects native maximization rather than fullscreen.

An initial mobile lifecycle run reported **1051/1052**: its adjusted object count exceeded the allowance by one. Structural nodes/resources/timers/services were stable and orphan count was zero. An isolated rerun and the final-runtime rerun both passed **1052/1052**; the assertion was not weakened. Existing economy balance remains **22/24**, unchanged.

## Web and physical acceptance

Production rebuild command:

```powershell
& .\tools\mobile\build_mobile_playtest.ps1
```

The separate browser QA export overrides the main scene only in a disposable Linux mirror and restores that configuration afterward. It never replaces the published game with the journey fixture. Browser throttling initially hit the fixture's 30-second cast wait; its Web-only orchestration wait budget was extended while preserving all production timing/scheduling. Web runs two repeated journeys; native runs three. The final rendered Web run passed **630/630**. Left/right projections reached x=115.2/524.8; top/bottom reached y=105.6/336.0. All corner projections remained inside the same rectangle.

The final production Linux rebuild completed successfully: published `index.pck` is **32,464,032 bytes**, and its `project.binary` is **9,970 bytes** with a valid **ECFG** header. The regular production main scene is preserved. Safari can refresh the existing address now.

Rendered browser evidence: `build/mobile-web/safe-rectangle/web-final.png` (ignored QA artifact). This shows normal water play and the yellow guide; deterministic off-terrain endpoint fixtures prove containment, not final artistic framing.

HTTPS is not restarted. The temporary loopback QA server is removed after acceptance checks. Physical iPhone bounds approval remains pending, so the yellow guide stays enabled. Verify left/right/top/bottom/corners, deep/submerged bait, current drift, retrieve/result dismissal, and no camera movement inside the rectangle in Safari. Confirm Windows title-bar drag from maximized state and Snap/divider gestures if not covered by your Floating test.

## Files changed

- `scripts/camera_rig.gd`
- `scripts/fishing_fight_camera_tracking.gd`
- `scripts/ui/fishing_safe_region_debug.gd` and `.gd.uid`
- `scripts/desktop/desktop_companion.gd`
- `tools/desktop/windows_appbar.py`
- `scripts/qa/fishing_fight_camera_tracking_qa.gd`
- `scripts/qa/passive_fishing_qa.gd`
- `scripts/qa/seaside_shell_layout_qa.gd`
- `scripts/qa/fishing_safe_rectangle_qa.gd`, `.gd.uid`, and `.tscn`
- `scripts/qa/desktop_floating_qa.gd` and `.gd.uid`
- `tools/desktop/verify_companion_floating.py`
- `export/index.html`, `export/index.pck`
- This report.

Temporary scripts/logs/captures are confined to ignored `build/mobile-web/safe-rectangle/`. Existing shader-cache write diagnostics and unrelated Web invalid-UID fallback warnings were not suppressed or repaired in this pass.
