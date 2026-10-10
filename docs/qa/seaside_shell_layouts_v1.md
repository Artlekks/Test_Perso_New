# Seaside gameplay shell layouts v1

Implemented the four supplied reference compositions: mobile landscape A, mobile portrait B, desktop wide C and desktop narrow D. The two mobile movement controls retain the existing circular touch control. Panel, button and icon artwork was extracted from the supplied references; no new generated art was introduced.

## Shared architecture and switching

`SeasideShellLayout` computes rectangles, `SeasideShellView` renders the shared skin and reads current state, and `SeasideShellActions` forwards utility actions to existing systems. The existing mobile harness and desktop companion each host this view. There are no four independent replacement game scenes.

- Mobile switches by safe-area aspect: width greater than height selects landscape; otherwise portrait. Orientation supports sensor rotation.
- Desktop logical window width **900 px or greater** selects wide; below 900 selects narrow. Docking and fullscreen continue through the existing platform adapter.
- The world remains **640 × 480**, uniformly scaled without cropping or changing the camera. At 390 px portrait width its framed gameplay surface is **378 × 283.5 logical pixels**, with 6 px horizontal frame margins. Existing independent menu scrolling and HUD surfaces remain intact.
- Layout switches preserve the game instance, physical bait, Passive state and timer deadline. Passive timer entry remains conditional, with no reserved Active timer panel.
- A/B/C/L/R retain K/I/named card challenge/Q/E. Menu retains J. Inventory, Journal and Settings open the existing Equip, Data and Options pages. Options includes access to the existing F10 playtest tools. Contextual Start match and QA / Playtest buttons forward existing Enter and Space actions; they do not create replacement gameplay flows.
- Location, spot, loadout, lure count and mode read existing authoritative state. Desktop controls display actual current bindings.

## Changed files

Production scripts:

- `scripts/ui/seaside_shell_layout.gd` and `.gd.uid` — new shared geometry.
- `scripts/ui/seaside_shell_view.gd` and `.gd.uid` — new shared visual view.
- `scripts/ui/seaside_shell_actions.gd` and `.gd.uid` — new action adapter.
- `scripts/mobile/mobile_portrait_harness.gd`
- `scripts/mobile/mobile_touch_controls.gd`
- `scripts/desktop/desktop_companion.gd`
- `scripts/desktop/companion_keyboard_strip.gd`
- `project.godot` — mobile orientation changed to sensor. The already-present removal of `window/stretch/aspect="keep"` was preserved.

New artwork under `assets/ui/seaside_shell/`: `a.png`, `b.png`, `button.png`, `c.png`, `cards.png`, `inventory.png`, `journal.png`, `keycap.png`, `l.png`, `landscape_l.png`, `landscape_r.png`, `panel.png`, `preview.png`, `r.png`, `rod.png`, `settings.png`, and each corresponding `.png.import` file.

QA scripts:

- `scripts/qa/seaside_shell_layout_qa.gd` and `.gd.uid` — new rendered layout/input/state fixture.
- `scripts/qa/mobile_qa_canvas.gd` — new explicit headless phone canvas fixture; production uses actual logical/CSS pixels.
- `scripts/qa/session_test_fixture.gd`
- `scripts/qa/mobile_portrait_harness_qa.gd`
- `scripts/qa/canonical_portrait_surface_qa.gd`
- `scripts/qa/mobile_presentation_standard_qa.gd`
- `scripts/qa/developer_playtest_qa.gd`

Delivery artifacts: `export/index.html`, `export/index.pck`, and this report. No actor scenes or fishing mechanics/camera scripts changed.

## Verification actually run

Godot executable: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`.

For headless rows, the command is that executable with `--headless --path . --script res://scripts/qa/<script>` and the listed arguments. Rendered rows use `--path . --rendering-method gl_compatibility --script res://scripts/qa/<script>` instead. Tests used isolated QA state. Native docking fixtures ran sequentially.

| Script | Extra arguments / execution | Result |
| --- | --- | --- |
| `seaside_shell_layout_qa.gd` | Rendered Compatibility | **91/91** |
| `mobile_portrait_harness_qa.gd` | Headless | **138/138** |
| `mobile_portrait_harness_qa.gd` | Rendered, `-- --rendered` | **145/145** |
| `canonical_portrait_surface_qa.gd` | `-- --mobile` | **526/526** |
| `mobile_presentation_standard_qa.gd` | Headless | **249/249** |
| `developer_playtest_qa.gd` | Headless | **90/90** |
| `desktop_companion_docking_qa.gd` | Rendered Compatibility | **587/587** |
| `passive_fishing_qa.gd` | Headless | **93/93** |
| `fishing_fight_camera_tracking_qa.gd` | Headless | **187/187** |
| `mobile_gameplay_parity_qa.gd` | Rendered, `-- --rendered` | **53/53** |
| `runtime_lifecycle_qa.gd` | `-- --mobile` | **1052/1052** |
| `session_contract_runner.gd` | Headless | Full fishing **22950/22950**, session contract PASS, 0 orphan nodes |
| `git diff --check` | Git | PASS |

Full regression also reports Fight 24/24, Presentation 10/10, Bite Timing 14/14, Stability 27/27, Fresh Save 55/55, Triple Triad 101/101, Crafting 14/14 and Card Maker 10/10. Dedicated economy guardrails remain **22/24**, with the known provisional H12 alerts unchanged.

QA expectations were updated for the reference frame and utility actions. The headless fixture now explicitly provides a phone-sized canvas instead of relying on the old production portrait scaling. A scrolling gutter assertion samples the actual 20 px gutter rather than assuming it occupies 10% of every viewport. Existing gameplay input and scrolling checks remain exercised.

Rendered native captures were inspected at 390×844, 844×390, 1200×860 and 480×900. The new fixture exercises utility buttons through actual touch input, breakpoint transitions during an active Passive cast, physical bait identity, timer preservation and native dock/fullscreen ownership. Captures and logs are in ignored `build/mobile-web/shell-layout/`.

The exported game was additionally loaded in the in-app Chromium browser at 390×844, 390×664 and 844×390. The live game rendered with no `SCRIPT ERROR` entries. This does **not** constitute physical Safari acceptance or pixel-perfect comparison with the illustrations.

## Web delivery

Rebuilt using:

```powershell
& .\tools\mobile\build_mobile_playtest.ps1
```

Validated Linux/WSL Godot 4.7.2 export: `index.pck` **32,446,912 bytes**; internal `project.binary` **9,970 bytes**, valid **ECFG** header. HTML/JS/WASM/PCK basename checks passed. Safari build artifacts are regenerated.

The HTTPS helper was neither started nor restarted. At final verification no listener was present on port 8060. The temporary read-only loopback QA server on 8079 was removed after testing.

## Remaining limitations and acceptance

- Physical iPhone Safari acceptance remains pending: refresh the rebuilt export, check both orientations, A/B/C/L/R, movement plus simultaneous actions, menus and cast/retrieve HUD. On desktop, check visual proportions at your preferred dock widths and fullscreen.
- There is no game-day clock in current state. The shell explicitly shows **Local HH:MM**, not invented Day 2/time progression.
- There is no authored location-thumbnail catalogue. The supplied seaside illustration is used for Beach; other locations do not receive a fabricated preview. Rod artwork is the reference illustration; names and lure images/counts are live data.
- Settings uses the existing Options page, not a new settings implementation. Existing mouse behavior is preserved; the controls strip does not introduce click-to-walk or click-to-cast mechanics.
- Existing rendered GLES shader-cache write diagnostics and Web invalid-UID fallback warnings remain environment/resource diagnostics outside this layout pass; they were not suppressed or repaired here.
