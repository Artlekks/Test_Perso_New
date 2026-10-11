# Fishing HUD spacing normalization

## Implementation

Only PowerMeterView's horizontal layout rule changed. The previous rule translated both gauges according to the vertical meter's 532/640 screen-width anchor. That created increasingly large character-to-HUD separation on the 960-wide landscape surface.

The new rule resolves the physical actor above Caster's ReelEndPoint, obtains its shared GroundPresentation, and samples the lower-body alpha bounds of Fishing_Idle frame 0 once per actor. It excludes transparent padding, hair and the raised rod from the stance measurement. A stable stance point is projected by the active gameplay camera, independently of the current cast/reel/bite animation. This avoids per-animation HUD shifts.

Power-bar X = projected reference stance right + power-bar height * `character_to_bar_gap_ratio` (default **0.25**, currently **14 gameplay pixels**). Both gauges receive the same translation. Their authored origin separation (357px), artwork gap (9.8px), Y positions, artwork dimensions/scales and entry/exit slide progress remain unchanged. The whole group is constrained against actual viewport bounds only if space is insufficient. There are no desktop/mobile breakpoint offsets or camera writes.

The image sample is cached; image decompression is supported for imported/Web textures. Runtime projection uses the physical actor's current world position and active gameplay camera, not Safari/window size. The initial missing-actor state retains a safe authored placement until the actor binding becomes available. Tests assert that real gameplay resolves the actual actor rather than using that fallback.

The real BOF4 reference screenshots, including the requested last screenshot, were not available among the current accessible images/project files. This is a measured compact-spacing correction; no exact BOF4 screenshot measurement or physical-phone acceptance is claimed.

## Before/after measurements

All values below are **gameplay pixels**, before shell display scaling. Actual visible-body clearance is measured in the power bar's vertical band by rendering the actor visible/hidden in the same engine frame. It deliberately excludes rod pixels above the HUD. The stable reference stance differs slightly from the current reel animation's body silhouette; its clearance is also recorded separately.

| Layout | World | Visible body → power before | After | Reference stance → power before | After | Bar → meter before/after |
|---|---|---:|---:|---:|---:|---:|
| Desktop wide, 1280x900 | 640x480 | 86.0 | 36.32 | 63.67 | 13.99 | 9.80 / 9.80 |
| Desktop compact, 640x900 | 640x480 | 86.0 | 36.32 | 63.67 | 13.99 | 9.80 / 9.80 |
| Mobile portrait, 390x844 | 640x480 | 86.0 | 36.33 | 63.67 | 14.00 | 9.80 / 9.80 |
| Mobile portrait, 320x568 | 640x480 | 86.0 | 36.33 | 63.67 | 14.00 | 9.80 / 9.80 |
| Mobile landscape, 932x430 | 960x480 | 192.0 | 36.33 | 169.67 | 14.00 | 9.80 / 9.80 |
| Mobile landscape, 568x320 | 960x480 | 192.0 | 36.33 | 169.67 | 14.00 | 9.80 / 9.80 |

Power/meter origins: 640-wide **175/532 → 125.33/482.33**; 960-wide **441/798 → 285.33/642.33**. Power artwork remains 347.2x56, scale (.35,.35); depth artwork remains approximately 47.52x102.24, scale (.36,.36). Desktop wide and compact use the same canonical 640-wide world and uniformly scale the entire gameplay display. Landscape player position stays (.236077,.893651), portrait/desktop (.104116,.893651), within the existing floating-point tolerance.

Rendered screenshots and measurements are under `build/mobile-web/hud-spacing/desktop/` and `build/mobile-web/hud-spacing/mobile/`. Inspected desktop wide, portrait and landscape captures. Constrained variants are also captured and checked for clipping, body overlap, stable animation-state layout, unchanged scale, live lure/HUD clearance, unchanged camera pose, yaw/return ownership, and physical input integration.

## Verification

Actual Godot executable: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`.

Commands were run using the existing isolated `build/mobile-web/root-repair/run.py` (adds `--headless --path <project>`) and `render_run.py` (adds `--rendering-method gl_compatibility --path <project>`). Logs use the names below. Wrappers redirect APPDATA/LOCALAPPDATA into ignored scratch; normal saves are untouched.

| Arguments | Log | Result |
|---|---|---|
| `--editor --import --quit` | hud-ratios-import-final | exit 0; no script compilation errors |
| `--script res://scripts/qa/fishing_camera_hud_stability_qa.gd` (rendered) | hud-ratios-mobile-final | **87/87** |
| same, `-- --desktop` (rendered) | hud-ratios-desktop-final | **45/45** |
| `--script res://scripts/qa/empty_lure_retrieval_qa.gd` | hud-ratios-empty | **286/286** |
| `--script res://scripts/qa/fishing_fight_camera_tracking_qa.gd` | hud-ratios-fight | **199/199** |
| `--script res://scripts/qa/seaside_shell_layout_qa.gd` | hud-ratios-shell | **88/88** |
| `--script res://scripts/qa/mobile_portrait_harness_qa.gd` | hud-ratios-touch | **153/153** |
| `--script res://scripts/qa/mobile_gameplay_parity_qa.gd` | hud-ratios-parity | **49/53**, unchanged four pre-existing foot-Y failures |
| `--script res://scripts/qa/session_contract_runner.gd` | hud-ratios-full | full fishing **22950/22950**; structural contracts PASS, stability **27/27**, presentation **10/10**, fight **24/24**, Triple Triad **101/101**; zero orphan nodes |
| `git diff --check` | terminal | exit 0 |

Existing engine GLES shader-cache write diagnostics occurred in rendered tests and were not suppressed. Explicit impossible-framing camera tests retain their diagnostics. Known economy balance 22/24 and mobile parity 49/53 remain visible and unchanged. An initial development test accidentally used ReelEndPoint as the actor; this was corrected to resolve its physical actor ancestor, and focused QA now explicitly rejects the fallback.

## Files changed by this pass

- `scripts/power_meter_view.gd`
- `scripts/qa/fishing_camera_hud_stability_qa.gd`
- `docs/qa/fishing_hud_spacing_v1.md` (new)
- `export/index.html`, `export/index.pck` (Linux rebuild)

Camera, character placement, steering, fishing mechanics, artwork scales, shell layout, window management and input mappings were not changed. Other pre-existing dirty files were left untouched.

Web rebuilt through `.\tools\mobile\build_mobile_playtest.ps1`, existing Linux/WSL Godot 4.7.2 workflow. Validated PCK: **32,587,872 bytes**; internal project.binary **9,970 bytes**, valid **ECFG** header. HTTPS remains running. Physical Safari acceptance and comparison against the unavailable real BOF4 image remain manual follow-ups.
