# Responsive Mobile UI v2 verification

Verified with Godot 4.7.2 on 2026-10-11. This is a shared mobile-shell presentation change. Camera, fishing, card rules, economy, desktop window management and save code were not edited.

## Implementation

Landscape calculates the largest height-limited 4:3 world first, then checks whether the remaining width can accommodate separate touch controls. Minimum usable footprints are 80 px on the left and 124 px on the right, with a 6 px game frame. They are compact input regions, **not** parchment panels. Remaining width stays charcoal burgundy. On constrained widths, the game is reduced only enough to fit these non-overlapping controls. On wider phones, available height determines game size.

Portrait uses an 80 px two-row environmental header, a width-dominant 4:3 game, and at least 224 px for controls. If height cannot support both the full-width game and usable controls, the game scales down uniformly. It is never cropped. Control space begins immediately below the game frame and ends at the bottom safe inset. The old permanent equipment header and four-button utility row are removed.

Both orientations use the same controls geometry, environmental data adapter, equipment drawer, nine-slice parchment/burgundy assets and existing gameplay input paths. A is 12% larger than the other face buttons. Face targets are circular, preventing ambiguous hits where their rectangular bounds overlap. All permanent buttons have at least 44 px height/diameter in the tested sizes. Stick zones are at least 72 px wide. Input strengths, dead zone, steering and reference-counted multitouch ownership are unchanged.

Mappings: A → K; B → I; X → one `world_card_challenge` action press/release; Y → J; L/R → Q/E; Start → Space pause/resume. Select and Gear are real shared-shell buttons opening the equipment drawer and existing Settings respectively. Select does not dispatch F10. The legacy keyboard/debug shortcut remains separate.

The drawer displays the selected rod and the current authoritative unified lure/bait item and count. The project has no independent lure/bait/line equipment simulation to fabricate. Pin/unpin is runtime presentation state; Change equipment opens the existing Equip menu. A pinned drawer temporarily hides for full modals and restores afterward. The shortest portrait drawer is top-aligned within the world so it does not obscure L/R. Opening/pinning never changes world geometry.

Weather, current and tide read the existing authored condition/current services. Current samples the physical bait when valid, otherwise the player. Wind and game day/clock explicitly show N/A. Current is unavailable until its spot/service is configured; no values are invented. Compact labels are reduced before values. Location/area names come from the existing world/HUD data, so this build displays “Beach”, not an invented “Seaside Beach” name.

## Measured rendered geometry

Units are logical/CSS-equivalent pixels, measured from actual native Compatibility-rendered harness execution. The safe-area fallback used for these reference captures is 47 px left/right and 21 px bottom in landscape; 47 px top and 34 px bottom in portrait. A real browser's reported safe insets override these fallbacks.

Game percentage = game rectangle area / usable safe rectangle area, including header and controls in the denominator. L/R below are control-region sizes, not background-panel sizes.

| Viewport | Usable safe size | Gameplay | Usable area % | Header | Left controls | Right controls |
|---|---|---|---:|---:|---|---|
| 568×320 | 474×299 | 258×193.5 | 35.2% | 52 | 80×247 | 124×247 |
| 667×375 | 573×354 | 357×267.75 | 47.1% | 52 | 80×302 | 124×302 |
| 844×390 | 750×369 | 406.67×305 | 44.8% | 52 | 80×317 | 124×317 |
| 932×430 | 838×409 | 460×345 | 46.3% | 52 | 80×357 | 124×357 |
| 320×568 | 320×487 | 228×171 | 25.0% | 80 | 160×224 | 160×224 |
| 375×667 | 375×586 | 360×270 | 44.2% | 80 | 187.5×224 | 187.5×224 |
| 390×844 | 390×763 | 378×283.5 | 36.0% | 80 | 195×387.5 | 195×387.5 |
| 430×932 | 430×851 | 418×313.5 | 35.8% | 80 | 215×445.5 | 215×445.5 |

At all eight sizes, all permanent controls are visible, inside the safe area and separate from gameplay. Face circles have at least 4 px separation; no duplicate press occurs. Header icons/values and compact labels were inspected in rendered exploration and fishing captures. There is no new permanent panel, header or control overlap with the game/HUD. The drawer intentionally overlays gameplay while open, but leaves permanent controls accessible. Full menus retain their existing separate scrollable UI surface; content taller than the visible game area scrolls rather than shrinking or cropping the 4:3 world.

320×568 is height-constrained: 228×171 is the maximum world with the chosen readable header and minimum comfortable controls. It does not claim full-width gameplay where that would force overlapping or smaller targets. At 375×667, height limits width slightly (360 rather than 363). The two taller portrait sizes fill the available width inside the frame.

### Comparison with rejected v1 landscape

| Viewport | Rejected v1 game | v2 game | Width gain | Game area gain |
|---|---|---|---:|---:|
| 568×320 | 206×154.5 | 258×193.5 | 25.2% | 56.9% |
| 667×375 | 305×228.75 | 357×267.75 | 17.0% | 37.0% |
| 844×390 | 387.44×290.58 | 406.67×305 | 5.0% | 10.2% |
| 932×430 | 433.33×325 | 460×345 | 6.2% | 12.7% |

The much larger visual improvement is removal of full-height parchment rails, including their unused width on height-limited devices. Neither comparison changes camera projection or the canonical render resolution.

## Render artifacts

`build/mobile-web/ui-v2/` contains `geometry.json` and four screenshot sets at **all eight sizes**:

- `explore-<width>x<height>.png`: closed drawer, exploration.
- `fishing-<width>x<height>.png`: real fishing entry, existing camera, active authored rain/current/tide service data.
- `drawer-<width>x<height>.png`: open pinned equipment drawer.
- `modal-<width>x<height>.png`: existing Equip modal; drawer temporarily hidden.

The rejected v1 captures were preserved in `build/mobile-web/ui-v2/before/`. Actual renders were inspected, including all eight exploration and fishing sizes, the shortest portrait drawer and representative landscape/portrait modal/drawer views. These are native rendered captures, not physical Safari screenshots. No claim of physical iPhone visual acceptance is made.

## Executed validation

Commands used the installed Windows executable:
`C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`
with `--path C:\Users\Alucard7th\Documents\FishingGame\fishing_game_clean_candidate_FRESH`. Test scripts use disposable profiles; the command wrapper also redirected APPDATA/LOCALAPPDATA beneath `build/mobile-web/root-repair/` to keep normal playtest saves/settings untouched.

| Godot arguments | Result |
|---|---|
| `--headless --editor --import --quit` | Exit 0; no GDScript compilation errors |
| `--rendering-method gl_compatibility --script res://scripts/qa/mobile_landscape_shell_qa.gd` | **442/442**, exit 0; both orientations, eight sizes, geometry, X events, real menu/settings/equipment, DEV card dialogue/match, fishing entry, drawer pin/modal/resize, teardown |
| `--headless --script res://scripts/qa/mobile_portrait_harness_qa.gd` | **153/153**, exit 0; real touch/drag, multitouch, card Normal Mode gates/acquisition/challenge, dialogue/merchant, pause, travel and releases |
| `--headless --script res://scripts/qa/seaside_shell_layout_qa.gd` | **88/88**, exit 0; shared shell and untouched desktop modes/geometry |
| `--headless res://actors/mobile/MobileWebParityQA.tscn` | **36/36**, exit 0; native execution of the Web-capable fixture, **not** browser DOM execution |
| `--headless --script res://scripts/qa/runtime_lifecycle_qa.gd -- --mobile` | **1052/1052**, plus full fishing **22950/22950** |
| `--headless --script res://scripts/qa/session_contract_runner.gd` | Full fishing **22950/22950**, orphan nodes 0; Triple Triad backend **101/101** included |
| `--headless --script res://scripts/qa/mobile_gameplay_parity_qa.gd` | **49/53**, exit 1: four pre-existing desktop/mobile synthetic fight-yaw foot-Y assertions remain failing; camera code unchanged |
| `git diff --check` | PASS; only Git CRLF-normalization notices |

The existing economy balance findings remain 22/24 with the two H12 alerts. They were not changed or suppressed.

QA updates replace obsolete portrait geometry/buttons/background expectations, retaining behavioral tests. The Web-parity fixture had two stale setup problems: `_enter_collection_for_profile()` focuses the deck rail, not the collection cursor; and a synthetic F10 closure has no touch release to satisfy the intentional modal release boundary. The fixture now selects the intended existing collection navigation state and performs a real Back press/release before the next world challenge. No card/gameplay guard was weakened. It also tears down the host before quitting, while original viewports remain live, eliminating fixture-only null-viewport teardown errors.

Rendered logs still contain existing engine GLES shader-cache write diagnostics (`_save_to_cache`, `f.is_null()`); they were not suppressed. Import also notices the ignored prior baseline QA copy's `project.godot` beneath `build/`. No production parser error was found. The known foot-Y parity failures remain a separate camera issue, outside this UI pass.

## Web delivery and physical limitations

Executed `& .\tools\mobile\build_mobile_playtest.ps1` using the existing validated Linux/WSL Godot 4.7.2 exporter and `Mobile Portrait Web Playtest` preset. Result: **32,558,292-byte PCK**, `project.binary` **9,970 bytes**, valid **ECFG** header. Export completed successfully to `export/index.html`. HTTPS was not started or restarted. Refresh the existing Safari URL.

Safari's viewport and safe-area values remain authoritative. Browser toolbar space is already absent from the available viewport supplied to layout; it cannot be recovered by the Godot UI. For the reference landscape captures, fallback safe insets alone remove 94 px width and 21 px height. Additional toolbar height reduces the height-limited game proportionally (each lost height pixel can remove up to 1.33 px game width). The constrained widths are already control-width-limited until height falls further. Standalone home-screen display can provide a taller viewport; no browser-chrome hiding was added.

Physical Safari acceptance remains: rotate both ways with toolbars visible, check cutouts/home indicator, continuous stick plus A/B/X/Y touches, pin/unpin and Equip/Settings scrolling, and inspect compact header readability on the phone. Native rendered QA verifies geometry/input paths; it cannot prove finger comfort or Safari-specific event delivery.

## Files changed

V2 edits:

- `scripts/ui/seaside_shell_layout.gd`
- `scripts/ui/seaside_shell_view.gd`
- `scripts/ui/seaside_environment_strip.gd`
- `scripts/mobile/mobile_touch_controls.gd`
- `scripts/qa/mobile_landscape_shell_qa.gd` (existing v1 filename retained; now covers both orientations)
- `scripts/qa/mobile_portrait_harness_qa.gd`
- `scripts/qa/mobile_web_parity_qa.gd`
- `scripts/qa/seaside_shell_layout_qa.gd`
- `docs/qa/responsive_mobile_ui_v2.md`
- Rebuilt `export/index.html` and `export/index.pck`

The two already-untracked v1 UID companions (`mobile_landscape_shell_qa.gd.uid`, `seaside_environment_strip.gd.uid`) remain unchanged. `index.js`/`index.wasm` were rebuilt/validated by the same exporter but are byte-identical, so Git does not list them as changed. Runtime, camera, economy, card mechanics, serving and certificate files were not edited.
