# 2.5D Grounding Visual Tuning v1.1

The physical-root grounding architecture is retained. No actor scene, collider,
camera controller, gameplay input, shadow transform, or fishing mechanic changed.
Card Maker smoke remains disabled. No new art was generated.

## Measured cause and correction

Most apparent separation came from the broad blob footprint, not vertical sprite
registration. The shared visual lift remains 0.012; shadow ground lift remains
0.006 (gathering items retain their existing 0.010 / 0.004 lifts).

One sheet registration error was proved: all four `Stand_Interest` frames have
their lowest eight-row contact span at source X=8..16, midpoint X=12, in a
40-pixel-wide cell. The old implicit stance was X=20. This placed the standing
Triad NPC's contact band about 14.1 screen pixels away from its physical root in
the 640x480 test view. The Merchant profile now declares
`animation_feet_from_left_px = {"Stand_Interest": 12.0}`. This applies to everyone
using that sheet/state, including mirrored Triad sprites. Its projected midpoint
is now about 1.75 pixels from the root, entirely from the existing small visual
lift. No vertical feet padding or root transform was changed.

The shared component converts this source-space stance into SpriteBase3D pixel
offsets, respecting explicit horizontal flips. A flip changes UVs, so the stance
offset must also reverse sign; see the [Godot implementation](https://github.com/godotengine/godot/blob/master/scene/3d/sprite_3d.cpp).
This is sprite-sheet registration, not a camera-relative shadow translation.

Measurements project physical root, declared VisualAnchor, source alpha contact
band and shadow center for Ryu, Merchant, Crafter, Card Maker, Triad, Still Water
Master and crab, at four camera headings. Fixtures use the actual exploration
Q/E input-handler path and CameraRig quarter-turn tween, in both directions.
All isolated physical roots remain (0,0,0); declared feet remain (0,0.012,0);
shadow center remains (0,0.006,0). At the initial view these project to roughly
(320,270.77), (320,269.01), and (320,269.89), respectively.

| Actor / pose | Bottom padding | Contact-band midpoint distance from root, after |
|---|---:|---:|
| Ryu Idle_S | 70 px | 1.75 screen px |
| Merchant Bag_Search | 0 px | 6.37 screen px |
| Crafter Bag_Search | 0 px | 6.37 screen px |
| Card Maker idle_se | 5 px | 2.48 screen px |
| Triad Stand_Interest | 7 px | 1.75 screen px |
| Still Water Idle | 4 px | 5.53 screen px |
| Crab idle_s | 7 px | 2.04 screen px |

The contact-band midpoint is not automatically the physical stance: raised feet,
bags and capes make it asymmetric. QA requires root X to fall within the visible
lowest eight-row contact span with four-pixel tolerance, and vertical contact to
be within four pixels of the root. It does **not** misreport every midpoint as
being within four pixels. The unmodified Merchant/Crafter/Master spans already
contain the root. Only Stand_Interest required a horizontal correction.
All 28 world/projected tuples are saved by the QA script's `--measurements=` option.

## Contact footprint changes (world units, width = depth)

| Category / profiles | Old | New | Opacity, unchanged |
|---|---|---|---|
| Humanoid: merchant / card_maker / still_water | 0.38 / 0.36 / 0.32 | 0.22 each | 0.65 |
| Unspecified character profile default | 0.30 | 0.22 | 0.65 |
| Player | 0.24 | 0.18 | 0.65 |
| Crab | 0.14 | 0.10 | 0.60 |
| Gathering small: shell / seaglass | 0.08 | 0.05 | 0.35 |
| Gathering base | 0.10 | 0.07 | 0.35 |
| Gathering standard: driftwood / coastalherb / ironscrap / seaweed | 0.13 | 0.08 | 0.35 |
| Small grounded prop: request board | 0.14 | 0.10 | 0.40 |
| Grounded prop: lockbox / registrar | 0.24 / 0.28 | 0.16 / 0.18 | 0.40 |

These are reusable profile defaults, not scene-instance transforms.

## Shared direction selection and art inventory

`view_relative_direction.gd` flattens camera right/down vectors, projects world
facing onto them, and selects the established S,SE,E,NE,N,NW,W,SW sector order.
GroundPresentation alone resolves available views. Missing views choose the
nearest authored sector; canonical order breaks ties consistently. Empty art
sets preserve the current animation. No automatic front/back invention or
implicit mirroring occurs. View changes preserve animation phase and paused state.

Card Maker and crab publish parent-space locomotion facing and idle/walk pose;
the component converts that facing to world space, including standalone scenes
whose parent is a Viewport. Card Maker retains his last facing when stopping,
rather than forcing idle_se. Patrol displacement, speed, pauses and collision
policy are unchanged. Stationary NPCs retain their authored one-view animations
and pre-existing flips.

For future static directional art, set the profile's `default_directional_pose`
and `directional_animation_prefixes`, then add lowercase direction suffixes to
the frame resource, e.g. idle_n / idle_ne. Explicit aliases can map canonical
S,N,E,W to arbitrary front/back/right/left animation names. No NPC camera math
or code change is required. Movers use the same profiles and pose API.

| Sheet | Available views | Existing mirrors / missing art |
|---|---|---|
| Player | 8 idle and 8 walk slots | Existing baked mirrors preserved; all three idle east/west pairs are exact mirrors. Walk NE/NW: 6/6 mirrored, E/W: 5/6, SE/SW: 0/6. Player code and SpriteDirector are unchanged. |
| Crab | 8 distinct idle views; 4 effective diagonal walk views | Walk NW/SW are the two authored strips; NE/SE are explicit flip aliases. Idle opposite pairs are not pixel-identical mirrors. No cardinal walk art. |
| Card Maker | 4 diagonal idle and walk views | NE/SE authored; NW/SW baked exact mirrors (6/6 frames in every pair). No cardinal art. Smoke remains disabled. |
| Merchant sheet | 1 view, two state animations | Merchant, Crafter, Triad, most Masters, Gyosil and regional merchant families. Bag_Search and Stand_Interest are states, not front/back views. True alternative views need new art. |
| Still Water Master | 1 Idle view | True alternative views need new art. |
| Pure 2-view actor set | None currently | The resolver supports and tests two-sector sets; crab walk uses two source strips plus explicit mirrored aliases. |

The pure helper is checked against the **unchanged production player method** for
64 world-facing/camera-heading combinations. It does not take over player or
fishing animation selection.

## Verification

Windows tests use installed Godot 4.7.2 via Start-Process -Wait. Common arguments:
`--headless --path . --script res://scripts/qa/<suite>.gd`.

| Suite / actual command suffix | Result |
|---|---|
| world_grounding_standard_qa.gd | 1025/1025 headless; 1029/1029 rendered Forward+ and Compatibility |
| world_presentation_tuning_qa.gd | 265/265 final; source-alpha projections, player equivalence, 8/4/2/1 nearest views, Q/E tween path, fixed roots/shadows, phase preservation, static profile-only activation, standalone parent handling |
| world_interaction_qa.gd | 93/93 |
| beach_collision_qa.gd | 65 checks, zero failures; Card Maker patrol / ghost-collider gate |
| world_actor_collision_qa.gd | 96/96, max passive displacement 0.0, epsilon 0.00001 |
| mobile_portrait_harness_qa.gd | 163/163 assertions; teardown reports 76 resources still in use (see limitation below) |
| fishing_fight_camera_tracking_qa.gd -- --regressions | Camera 120/120; full fishing 22950/22950 |
| Existing startup QA in the above integration runs | Card Maker 10/10; Fight 24/24; Presentation 10/10; Stability 27/27; Fresh Save 55/55 |
| Linux-built MobileWebParityQA.tscn at disposable loopback origin, `?shadow_orbits=1` | 48/48: actual DOM touch C/confirm, route parity, four views of Ryu/Merchant/Card Maker/Master, fixed transforms and predictable art |

Rendered runs use `--rendering-method forward_plus` or `gl_compatibility`, omit
`--headless`, and append `-- --rendered --capture-dir=<artifact directory>`.
The tuning script also accepts `--measurements=<JSON path>`.
Controlled `--baseline-footprints` runs restore old profile dimensions and old
horizontal registration **only in disposable actors**; they reproduce the four
Triad contact failures (261/265), while the final profiles pass 265/265.

The first expanded Web fixture incorrectly assigned its getter-only `paused`
wrapper instead of pausing the SceneTree, so a roaming Card Maker failed three
stationary-root checks (45/48). The fixture now pauses the real SceneTree and
hides other actors for clear captures. Final Web runs pass 48/48. Production
pause/movement behavior was not changed.

Native source-alpha measurement loads raw source PNGs intentionally; Godot warns
that this source-loading method is not export-safe. It runs only in native QA;
the exported Web fixture uses normal imported textures and transforms instead.
Native mobile QA exits zero with all assertions passing, but emits a shutdown
`76 resources still in use` error. Its cleanup cause is not diagnosed in this
presentation pass; it is not claimed as a completely clean shutdown. No failure
was swallowed. Known provisional economy findings remain 22/24.

Physical iPhone Safari visual acceptance still requires refreshing the build and
using L/R around the same actors. Rendered desktop/Web checks do not substitute
for physical-device acceptance.

## Build

The final production export is built with the existing validated Linux helper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1
```

The production mobile main scene remains MobilePortraitHarness. The QA build is
separate; it never replaces the production export. HTTPS is not restarted.
Final production PCK: 31,279,612 bytes. `project.binary`: 9,944 bytes, valid ECFG
header; validation includes entry checksum and matching export basenames.
The existing HTTPS listener remains PID 2964 on 0.0.0.0:8060.
`git diff --check` passes.

## Complete project file changes for this pass

- data/presentation/card_maker.tres
- data/presentation/coastalherb.tres
- data/presentation/crab.tres
- data/presentation/driftwood.tres
- data/presentation/ground_item.tres
- data/presentation/harborlockbox.tres
- data/presentation/harborrequestboard.tres
- data/presentation/ironscrap.tres
- data/presentation/merchant.tres
- data/presentation/player.tres
- data/presentation/regionalchampionshipregistrar.tres
- data/presentation/seaglass.tres
- data/presentation/seaweed.tres
- data/presentation/shell.tres
- data/presentation/still_water.tres
- docs/mobile/grounding_visual_tuning_v11.md (new)
- export/index.html (regenerated)
- export/index.pck (regenerated)
- scripts/economy/fishing_card_maker_npc.gd
- scripts/qa/mobile_web_parity_qa.gd
- scripts/qa/world_grounding_standard_qa.gd
- scripts/qa/world_presentation_tuning_qa.gd (new)
- scripts/qa/world_presentation_tuning_qa.gd.uid (new)
- scripts/world/beach_fishing_critter.gd
- scripts/world/ground_presentation.gd
- scripts/world/view_relative_direction.gd (new)
- scripts/world/view_relative_direction.gd.uid (new)
- scripts/world/world_actor_presentation_profile.gd
