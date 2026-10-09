# Canonical Portrait Game Surface v1

The game composes at **640 × 864 logical pixels (20:27)** on every host. The
mobile shell does not change game geometry. There are no separate phone menu
controllers, transaction implementations or card ownership stores.

## Hosts

Desktop defaults to a portrait game window. From the project directory:

```powershell
& .\tools\desktop\run_portrait.ps1
& .\tools\desktop\run_portrait.ps1 -Fullscreen
```

Godot's `canvas_items` stretch with `keep` aspect uniformly scales the same
composition and letterboxes/pillarboxes wide windows and fullscreen. Output
rectangle rounding can produce less than one physical pixel of difference
between reported X/Y stretch factors. Logical geometry remains 640×864.

The iPhone 13 Pro reference is 390×844 CSS/logical pixels, with 47 top and 34
bottom safe insets. The game occupies **390×526.5** at scale **0.609375**;
controls occupy **390×236.5**, beginning at Y=573.5 and ending at Y=810.
Short Safari windows reduce the game's uniform scale instead of changing its
canvas. The controls keep their safe column width and minimum height. The external floating joystick and A/B/C/L/R/
MENU/SELECT/START mapping are unchanged. Reference targets remain at least
44×44 CSS pixels. Phone chrome/orientation and physical readability still
require iPhone acceptance; desktop harness captures are not physical Safari.

## Shared components

- `scripts/ui/portrait_ui.gd`: resolution, 18px baseline, BOF font, nearest
  filtering, shared cached Panel.png style, panel/rectangle helpers and input
  hint presentation. Panel border construction reuses the approved dialogue
  panel helper; dialogue itself is unchanged.
- `scripts/ui/canonical_game_surface.gd`: the previously approved horizontal
  camera projection, fishing composition and bottom HUD anchoring, now used
  by both desktop and shell before child readiness. It does not change cast,
  fight, steering or camera tracking algorithms.
- `scripts/ui/triple_triad_portrait_layout.gd`: battle, deck and result geometry.
- `scripts/mobile/responsive_menu_surface.gd`: retained path for compatibility,
  now a shared read-only portrait view on **all** hosts. Existing controller
  labels, lists, recipes, quotes and preview textures remain authoritative.

Panels support headers, lists, details, actions and modals. Sections use 12px
outer/content spacing, high-contrast text, nearest filtering and scrollable
content. No presentation-layer duplication of prices or authored requirements.
The new menu surface stays owned by its menu but is a top-level CanvasItem so
legacy root scale/animation cannot distort it. Original decorations are masked;
their controller nodes remain available without displaying a second UI.

## Triple Triad

All card internals remain the authored **116×132** pixels. Battle hands formerly
used **74×88** with non-uniform `(0.637931, 0.666667)` scaling; deck/collection
formerly used **58×66** at 0.5; results formerly used **95.12×108.24** at 0.82.
All now use **116×132 at uniform 1×**. The transfer focus uses uniform 2×.

Battle hands occupy X=12 and X=512, Y=100, with a 140px vertical step. Five
fully visible cards end at Y=792. The central 356×404 board begins at (142,225),
with 4px gaps. Empty slots have shared panels independent of card artwork.
Header contains scores/round/turn; central contextual details and footer hints
remain separate from cards. Player/opponent ownership outlines are unchanged.

Deck has five full-size slots, saved profile selectors, three sort selectors,
**5 columns × 2 rows / ten cards per page**, scrollable selected-card details,
budget/status and clear Play hints. Selecting a saved Deck focuses its slots;
confirming a slot focuses collection replacement. Replacement uses the existing
validated animation/commit operation and returns focus to that slot. Browsing
collection still supports existing add/remove. Empty slots are explicit panels.
ENTER confirms valid decks; the external START/Space mapping confirms on the
touch shell. No practice cards become owned cards.

Results retain five cards above and five below, automatic existing reward/loss
resolution and red/blue ownership outlines. No reward-choice step was added.

## Other migrated screens

Merchant/shop, Manillo/fish trade, fishing economy, lure crafting/customization,
Card Maker/card crafting and fishing inventory/status/equipment/data/help/hints
use HEADER → LIST → DETAILS → ACTIONS sections with scrolling when necessary.
Card Maker and inventory preview textures come from their original controllers.
Inventory fish records and requirement quantities remain controller outputs.
Options remains its existing unimplemented placeholder; no new gameplay was
invented. Confirmation stays in the same underlying controller.

Normal text in these migrated interfaces is at least **18 logical pixels**, at
effective 1× logical scale, with BOF_Font_Refined.fnt and no added outline. The
approved exploration/fishing HUD, location artwork and dialogue retain their
existing typography; debug interfaces are not new production menus.

Hint strings use one presentation helper: desktop K/I/ENTER/Q-E versus touch
A/B/START/L-R (J becomes MENU). Input routing and transaction logic remain shared.
Battle rotation retains desktop R and accepts E as a universal alias because the
unchanged touch R shoulder emits E. Both route to the same existing rotation
command; deck E paging and fishing controls remain unchanged.

## Retained artwork

No artwork was deleted. Menu_Background_Solo, CardGame_Background, CardGrid,
Deck_Screen, merchant/list/info blank textures and crafting/Card Maker structural
backgrounds remain stored and referenced by legacy authored scenes where
applicable, but no longer control the migrated production layout. Approved HUD,
dialogue panel, selectors, card portraits/numbers/frames and item previews remain.

## Verification

The focused fixture is `scripts/qa/canonical_portrait_surface_qa.gd`. It checks
logical size, phone shell geometry/targets, effective font scale, card bounds,
deck focus/replacement/pagination/reopening, unchanged owned quantities, result
rows, shared menu panels, window stretch/fullscreen and orphan-free teardown.
Rendered runs capture actual native and scaled iPhone-reference images under
`build/mobile-web/portrait-captures/`.

```powershell
$godot = "$env:USERPROFILE\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script scripts/qa/canonical_portrait_surface_qa.gd
& $godot --headless --path . --script scripts/qa/canonical_portrait_surface_qa.gd -- --mobile
& $godot --path . --rendering-method gl_compatibility --script scripts/qa/canonical_portrait_surface_qa.gd -- --rendered
& $godot --path . --rendering-method gl_compatibility --script scripts/qa/canonical_portrait_surface_qa.gd -- --rendered --mobile
& $godot --headless --path . --script scripts/qa/session_contract_runner.gd
& $godot --headless --path . --script scripts/qa/world_interaction_qa.gd
& $godot --headless --path . --script scripts/qa/mobile_portrait_harness_qa.gd
& $godot --headless --path . --script scripts/qa/mobile_presentation_standard_qa.gd
& $godot --headless --path . --script scripts/qa/developer_playtest_qa.gd
& $godot --headless --path . --script scripts/qa/deck_ownership_durability_qa.gd
& $godot --headless --path . --script scripts/qa/runtime_lifecycle_qa.gd
& $godot --headless --path . --script scripts/qa/runtime_lifecycle_qa.gd -- --mobile
git diff --check
& .\tools\mobile\build_mobile_playtest.ps1
```

Existing assertions expecting variable 640×863 game size, mobile-only text decks
or desktop-only dense geometry were corrected to the explicitly requested
canonical contract. Existing touch, transaction, ownership and gameplay assertions
were retained. Developer QA explicitly enters collection browsing after checking
new slot-first deck focus, preserving its add/remove/practice persistence tests.

Final QA results and changed-file inventory follow.
Known economy design alerts remain 22/24; this pass does not alter them. GLES
shader-cache write diagnostics remain environment-level diagnostics during
rendered QA; gameplay script errors are checked separately.

## Final results

| Check | Result |
| --- | --- |
| Canonical portrait, native headless | 506/506 |
| Canonical portrait, mobile headless | 523/523 |
| Canonical portrait, rendered native/fullscreen | 521/521 |
| Canonical portrait, rendered mobile/short Safari targets | 545/545 |
| Triple Triad backend | 101/101 |
| Beach crafting | 14/14, 36 recipe combinations |
| Card Maker | 10/10 |
| World interaction | 93/93 |
| Mobile portrait harness | 162/162 |
| Shared presentation standard | 252/252 |
| Developer Playtest | 90/90 |
| Deck ownership/save durability | 91/91 |
| Native lifecycle | 1832/1832 |
| Mobile lifecycle | 1052/1052 |
| Full fishing regression | 22950/22950 |
| Fishing Fight / Presentation / Stability | 24/24, 10/10, 27/27 |
| Campaign / Fresh save | 14/14, 55/55 |
| `git diff --check` | PASS |

Rendered counts vary with the number of currently visible contextual labels;
each visible text/control is checked. Captures were inspected for battle,
deck, result rows, merchant, crafting/Card Maker and inventory. Effective text
scale coverage caught and eliminated inherited inventory-root scaling. Actual
fullscreen reported `(1.851563, 1.851852)` with the same 640×864 logical canvas;
the difference is 0.25 physical output pixels across 864 logical pixels.
The extra short-Safari checks preserve full-width controls and contained 44px
targets without changing any touch mappings.

Six-cycle lifecycle samples stabilized at 2102 structural nodes / 2209 resources
on native and 2106 structural nodes / 2211 resources on mobile, one session,
zero orphan nodes and zero active tweens between cycles. Ambient shadow counts
and intentionally acquired specimens vary; structural counts do not accumulate.

Linux/WSL rebuild succeeded: `export/index.pck` is **32,161,732 bytes**;
`project.binary` is **9,887 bytes**, header **ECFG**. Basename integrity validation
passed. HTTPS was not restarted. Refresh Safari after the build command finishes.
Physical iPhone acceptance remains necessary for comfortable readability and
normal Safari browser-chrome behavior; the rendered harness is reference evidence.

## Complete changed-file inventory

Existing files modified:

```text
project.godot
scripts/beach_crafting_menu.gd
scripts/economy/fishing_card_maker_menu.gd
scripts/fishing_economy_menu.gd
scripts/fishing_menu.gd
scripts/mobile/mobile_portrait_harness.gd
scripts/mobile/responsive_menu_surface.gd
scripts/qa/developer_playtest_qa.gd
scripts/qa/mobile_portrait_harness_qa.gd
scripts/qa/mobile_presentation_standard_qa.gd
scripts/triple_triad/triple_triad_animation_director.gd
scripts/triple_triad/triple_triad_deck_setup.gd
scripts/triple_triad/triple_triad_input_controller.gd
scripts/triple_triad/triple_triad_match_hud.gd
scripts/triple_triad/triple_triad_presentation_controller.gd
scripts/triple_triad/triple_triad_reward_view.gd
scripts/triple_triad/triple_triad_surrender_confirm.gd
scripts/triple_triad/triple_triad_ui_flow_controller.gd
scripts/world/playable_location_scene.gd
export/index.html
export/index.pck
```

New files:

```text
docs/ui/canonical_portrait_surface_v1.md
scripts/qa/canonical_portrait_surface_qa.gd
scripts/qa/canonical_portrait_surface_qa.gd.uid
scripts/ui/canonical_game_surface.gd
scripts/ui/canonical_game_surface.gd.uid
scripts/ui/portrait_ui.gd
scripts/ui/portrait_ui.gd.uid
scripts/ui/triple_triad_portrait_layout.gd
scripts/ui/triple_triad_portrait_layout.gd.uid
tools/desktop/run_portrait.ps1
```
