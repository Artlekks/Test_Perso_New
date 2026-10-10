# Canonical Portrait Stabilization v1.1

## Fishing freeze: reproduced cause and correction

The rendered pre-fix mobile probe created a physical bait and entered phase 8
(`THROW`), but the player remained in `Prep_Throw_Idle`. The engine reported:

```
Invalid access to property or key 'economy_playtest_telemetry'
on a base object of type 'Node (FishingSessionServices)'.
_commit_curved_cast, scripts/fishing.gd:2115 (pre-fix)
```

Session Composition vs QA/Debug Separation had moved telemetry out of
FishingSessionServices. One production cast call still accessed the deleted
property. Its error occurred after bait creation and phase assignment, before
`sprite_director.play("Throw")`. Consequently, the Throw completion callback
could never run. `THROW` intentionally does not accept ordinary cancellation,
which explains why neither further input nor exit recovered that cast.

This was exposed by portrait acceptance, not caused by viewport scaling or
animation visibility. The previous harness QA assigned AIM and tested only
PREP_THROW; the model regression never executed this complete input path.

Fishing now plays Throw and emits `cast_started`. Optional runtime telemetry
subscribes while recording, using its existing weak owner/disconnection bucket.
Production fishing does not load or dereference a debug recorder. An existing
recorder is rebound by FishingDevelopmentLayer.mount_game on travel. This also
repairs the old recording travel regression exposed by the telemetry suite.

No fishing phase is forced forward. Cast physics, input gate, animation assets,
camera settings, encounter mechanics, bite timing, currents and retrieve return
remain unchanged.

## Full-width display policy

The old shell reserved 236 CSS pixels for controls, then reduced the game scale
to fit the remaining height. This caused horizontal pillarboxing in short Safari
windows. The shared logical game surface remains **640 Ã— 864**.

Portrait now uses `safe_width / 640` uniformly, with nearest filtering. A clipped
display window retains the bottom part of world play, including the fishing HUD.
Controls start directly below that window and retain their existing hit sizes.
During menus/dialogue/lure selection and catch results, the display begins at its top. Swipe upward/downward in
the rightmost 20 shell-coordinate pixels to expose the canonical surface below
or above the display window. Internal menu scrolling remains available separately.
Closing the modal restores the bottom-aligned world display. Manual pause alone
retains the bottom HUD. Published overlay visibility is tracked through bounded,
deduplicated weak handles; shell display policy never writes gameplay pause/state.

This short-window policy was explicitly approved by the user. It does not move
the camera or change the logical game/UI viewport. Upper world content is
deliberately cropped; the full menu surface remains reachable by display scrolling.

Reference geometry with 47 top / 34 bottom CSS-pixel safe insets:

| Window | Before: image | After: full image | After: visible display | Controls |
|---|---:|---:|---:|---:|
| 390 Ã— 844 | 390 Ã— 526.5 | 390 Ã— 526.5 | 390 Ã— 526.5 | 390 Ã— 236.5 |
| 390 Ã— 664 | 257.04 Ã— 347 | 390 Ã— 526.5 | 390 Ã— 347 | 390 Ã— 236 |

At the short reference size, 179.5 CSS pixels are cropped from the top during
world play. Actual Safari safe insets and browser chrome determine the live
visible height. Native simulated short-window output has fractional/whole-pixel
stretch quantization and uses fallback safe insets; it is not a physical Safari
measurement. The rendered Web fixture was also run with a 390 Ã— 664 CSS viewport.

## Controls and cards

Triple Triad cards are still native **116 Ã— 132**, preserving the five effective
card widths. No card or menu controller was redesigned in this pass.

Button hit-box origins for a 390 Ã— 236 control section (CSS-equivalent pixels):

| Button | Origin | Size |
|---|---:|---:|
| A | 312, 71.98 | 74.1 Ã— 74.1 |
| B | 222.3, 115.64 | 74.1 Ã— 74.1 |
| C | 206.7, 48 | 58.5 Ã— 58.5 |
| MENU | 5.85, 192 | 74.1 Ã— 44 |
| SELECT | 218.4, 192 | 78 Ã— 44 |
| START | 304.2, 192 | 78 Ã— 44 |

Existing hit sizes, mappings, stick ownership and L/R are unchanged. A/B/C form
a spaced triangle; SELECT/START form the right-hand footer group. Only origins
changed. The actual taller reference control section changes proportional Y
positions slightly. Bottom safe clearance remains outside the control section.

## Acceptance fixtures and scope

`actors/mobile/PortraitFishingAcceptance.tscn` executes actual entry/camera and
animation completion, touch confirms, physical casting and water entry, held
retrieve, recast, timed missed opportunity, real hook input, catch animation,
result dismissal and normal exit. It never assigns a fishing phase or advances
an animation manually. Three casts run per fixture.

Fish selection is deterministic through a fixture-only forced-fish provider.
Landing is triggered at the existing returned-bait boundary so result ownership
and animation are deterministic. These tests do **not** claim to validate natural
fight balance or a player's full stamina/tension strategy.

The short-display fixture drives actual display-gutter touch events while a real
inventory modal owns pause, verifies top/bottom access and non-overlapping touch
targets, and renders world/menu captures. Companion mode uses the same fishing
acceptance fixture with native keyboard events.

## Verification

Godot executable used:
`C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`.
All fixtures use disposable save directories; the Web acceptance build uses a
separate loopback origin and does not load the served phone save.

Commands below were run with `--path .`; rendered checks also used
`--rendering-method gl_compatibility`.

| Command / suite | Result |
|---|---:|
| `--script scripts/qa/portrait_fishing_acceptance_runner.gd` (rendered mobile, short window) | 47/47; three casts |
| Same fixture in Linux-generated rendered Web, browser CSS 390 Ã— 664 | 47/47; three casts; no script errors |
| Same runner `-- --companion` (rendered) | 91/91; three casts, mode cycles, menus/card match |
| `--script scripts/qa/mobile_portrait_layout_qa.gd` (rendered) | 44/44 |
| `--script scripts/qa/canonical_portrait_surface_qa.gd -- --rendered --mobile` | 572/572 |
| Same canonical QA `-- --rendered` (desktop/fullscreen) | 521/521 |
| `--headless --script scripts/qa/mobile_portrait_harness_qa.gd` | 162/162 |
| `--headless --script scripts/qa/mobile_presentation_standard_qa.gd` | 252/252 |
| `--headless --script scripts/qa/developer_playtest_qa.gd` | 90/90 |
| `--headless --script scripts/qa/session_composition_separation_qa.gd` | 102/102; 12 alternating host lifetimes |
| `--headless --script scripts/qa/runtime_economy_telemetry_qa.gd` | 86/86 |
| `--headless --script scripts/qa/fishing_fight_camera_tracking_qa.gd` | 164/164 |
| `--headless --script scripts/qa/world_interaction_qa.gd` | 93/93 |
| `--headless --script scripts/qa/session_contract_runner.gd` | PASS; full fishing 22,950/22,950; zero orphan nodes |
| `--headless --script scripts/qa/runtime_lifecycle_qa.gd` | 1,832/1,832; six travel cycles |
| Same lifecycle QA `-- --mobile` | 1,052/1,052; six travel cycles |
| Native `--headless --editor --import --quit` | exit 0; no parser/resource errors |
| `git diff --check` | PASS |

The explicit session runner also reports Triple Triad 101/101, crafting 14/14
(36 combinations), Card Maker 10/10, fishing fight 24/24, presentation 10/10,
bite timing 14/14, stability 27/27 and fresh save 55/55. Economy balance remains
22/24 with the same two H12 provisional alerts; no values were changed.

Native rendered runs retain the known GLES shader-cache write diagnostics.
The Web build reports existing authored current-field UID fallback warnings
(`b8cv7hluf70by` versus the script's `b8cv7h1uf70by`); path loading succeeds.
Those unrelated resource references were not edited. No script errors occurred
in the final rendered fishing acceptance runs.

Rendered artifacts are under `build/mobile-web/portrait-captures/`, including
`acceptance-water.png`, `short-world.png`, `short-menu-top.png` and
`short-menu-bottom.png`. Logs are under `build/mobile-web/`.

## Files touched by this stabilization pass

This list excludes pre-existing uncommitted v1 changes untouched here.

- `scripts/fishing.gd`
- `scripts/telemetry/runtime_economy_telemetry.gd`
- `scripts/development/fishing_development_layer.gd`
- `scripts/mobile/mobile_portrait_harness.gd`
- `scripts/mobile/mobile_touch_controls.gd`
- `scripts/ui/portrait_ui.gd`
- `scripts/desktop/desktop_companion.gd` and generated `.uid`
- `actors/desktop/DesktopCompanion.tscn`
- `tools/desktop/run_portrait.ps1`
- `actors/mobile/PortraitFishingAcceptance.tscn`
- `scripts/qa/portrait_fishing_acceptance.gd` and generated `.uid`
- `scripts/qa/portrait_fishing_acceptance_runner.gd` and generated `.uid`
- `scripts/qa/mobile_portrait_layout_qa.gd` and generated `.uid`
- `scripts/qa/canonical_portrait_surface_qa.gd`
- `scripts/qa/mobile_portrait_harness_qa.gd`
- `scripts/qa/mobile_presentation_standard_qa.gd`
- `scripts/qa/runtime_economy_telemetry_qa.gd`
- `docs/ui/canonical_portrait_stabilization_v1_1.md`
- `docs/platform/desktop_companion_foundation_v1.md`
- Rebuilt `export/index.html` and `export/index.pck`; the other same-basename
  export artifacts are rebuilt/copied but remain byte-identical if unchanged.

## Physical acceptance still needed

Refresh the existing HTTPS phone address. Verify repeated casts/retrievals,
normal exit and catch dismissal, full width with Safari chrome present, the
bottom fishing HUD, gutter scrolling in long menus, and A/B/C spacing on the
physical iPhone. Rendered Windows/Web execution is verified; this report does
not claim a new physical Safari acceptance.

Daily rebuild remains `& .\tools\mobile\build_mobile_playtest.ps1` (Linux/WSL).
It validates `project.binary`/ECFG before publication. HTTPS was not restarted.

Final published build validation: PCK **32,183,368 bytes**;
`project.binary` **9,887 bytes**, header **ECFG**. The final acceptance export is
separate from `export/`; it does not replace the normal phone entry scene.
# Morning Stability v1 presentation contracts

The canonical surface remains 640Ã—864. Catch Data, rank and points use one
composed group centered in the visible gameplay rectangle. Mobile crop height
is published by the harness; touch controls are excluded. Desktop letterbox,
header and keyboard strip are excluded. Existing item/card notices retain their
own presentation rather than being converted into fish Data panels.

Responsive merchant, crafting, Card Maker and inventory row selectors reuse
`Menu_Hint_Panel_Selector.png`, nearest-filtered and drawn above row text/dimming.
Crafting recipe navigation scrolls separately from the fixed material/detail
stack; selection changes cannot translate the detail panel.

Fishing camera edge state is HOLD / PAN_LEFT / PAN_RIGHT. Outer thresholds are
12% / 92%; per-edge stop thresholds are 14% / 90%. A bait in the central safe
rectangle keeps the exact current yaw, with no neutral-return chasing. Vertical
HUD clearance remains part of the orbit solver. Â±55Â°, response 6, retrieve
return response 2, A/D aim and physical bait movement are preserved.

The authored `fish_ripple.png` presentation uses pixel size .00175 (50% of
.0035); source art and stronger splash size are unchanged. Ripple represents
the entire hook opportunity; only committed take uses splash. Ready INSPECT
engagement uses exported `engaged_bite_opportunity_chance=.70`; an ambient
nearby shadow alone retains ordinary polling probability.
