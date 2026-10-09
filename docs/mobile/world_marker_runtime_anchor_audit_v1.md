# World Marker Runtime Anchor Audit v1

2026-10-09; Godot 4.7.2. Native rendered execution used Compatibility/GLES3.

## Diagnosis proved in rendered execution

The reported Card Maker sliding was reproduced in the actual
`FishingTestScene_V2` camera. No physical marker node translates with camera yaw:
ActorRoot, GroundPresentation, WorldMarkerAnchor, RequestMarker and its Label3D
all retain their world transforms while the camera rotates.

Card Maker's transform chain before the fix:

```text
FishingCardMakerNPC (CharacterBody3D; physical feet Y=0)
├─ GroundPresentation (world-aligned actor-root anchor)
│  └─ VisualAnchor (+0.012m ground lift)
│     └─ AnimatedSprite3D (full billboard; frame feet offset)
├─ WorldMarkerAnchor (actor world position + world UP × profile.marker_height)
└─ RequestMarker (top-level compatibility node; copies physical anchor)
   └─ Label3D (billboard=1; zero local offset; centered)
```

In the live capture, the physical actor remained at
`(0.788921, 0, 0.519513)`, and the anchor/marker/label remained at
`(0.788921, 0.72, 0.519513)` through the whole orbit. The label had zero offset
and centered horizontal/vertical alignment. There was no camera-relative
positioning code in this chain.

The root cause is **perspective parallax**, not a marker-transform translation.
The exploration camera is steep and rolled; a point 0.72m vertically above the
feet has a different camera-space depth and projection from the full-billboard
body. Billboarding rotates a glyph's plane but does not change the projection of
its origin. Its apparent separation changes as the camera orbits. Previous QA
checked fixed world positions without measuring the rendered icon against the
projected body/feet, so it could pass while the visible behavior was wrong.

For example, one live orbit frame projected the feet to
`(483.3037, 232.2167)` and the old marker origin to `(586.8621, 133.4004)`:
**103.5584px sideways** despite unchanged world transforms. Other angles placed
the physically elevated icon below the screen-projected feet or off-screen.
Before/after screenshots and full transform traces are retained under
`build/mobile-web/marker-live-before` and `marker-live-after`.

The isolated actor-centered orbit did not reproduce this parallax. The live
authored-camera orbit did; that distinction was established before editing.

## User-approved presentation choice and implementation

The user explicitly selected:
**"Keep the icon visually overhead; allow screen-space icon placement while
retaining a fixed world anchor."** This supersedes the original restriction
against camera-dependent visual placement. Physical anchor placement remains
strictly camera-independent.

After:

```text
ActorRoot (physical position, collider and locomotion unchanged)
├─ GroundPresentation (body/directional sprites and shadows unchanged)
├─ WorldMarkerAnchor (fixed world-height point; profile-owned)
│  └─ MarkerCanvas (CanvasLayer 1 in the actor's viewport)
│     ├─ PromptLabel3DVisual (2D Label, always camera-facing)
│     └─ RequestMarkerVisual (2D Label where authored)
├─ PromptLabel3D (existing controller state source; 3D render layer 0)
└─ RequestMarker / Label3D (existing request state source; 3D render layer 0)
```

The shared adapter computes the visual center by projecting
`actor.global_position + camera.global_basis.y * profile.marker_height`.
That is a projection sample only: no node is moved to that camera-relative world
point. It places the icon exactly above the projected physical feet even when
the camera has pitch/roll. Physical WorldMarkerAnchor remains
`actor.global_position + Vector3.UP * profile.marker_height`.

The icon uses its original text/glyph, font (or the same fallback font), font
size, outline and colors. Its screen scale comes from the original Label3D pixel
size projected at actor depth, avoiding the old elevated-point magnification.
The existing `!`, `*`, `?` and prompt strings are unchanged. 2D visuals always
face the viewer, replacing 3D icon billboarding without rotating/moving actors.

The original controller paths and request visibility semantics remain intact;
no interaction, dialogue or quest controller needed edits. Only the new visual
renders, so there is no duplicate 3D glyph. Mouse filtering is IGNORE, and the
marker canvas remains below gameplay/dialogue HUD layers. Missing cameras and
actors behind the camera hide the visual. Profile reapplication refreshes the
shared anchor without creating duplicate canvases or labels. Actor destruction
also destroys its owned canvas/visuals; there is no global marker registry.

No camera, actor position, collision, interaction range, ground/shadow family,
directional art, economy, fishing or destination scene was modified. Legacy
source-label scene positions are not rendering authorities; profile marker
height is the single physical/visual height control (current default **0.72m**).

## Every marker-bearing actor migrated

All current NPC types inherit the same runtime installation, with no per-NPC
or per-destination adapters:

- BeachMerchantNPC
- BeachCrafterNPC
- FishingCardMakerNPC
- TripleTriadOpponentNPC
- FishingMasterStillWaterNPC
- FishingMasterCurrentReaderNPC
- FishingMasterDepthReaderNPC
- FishingMasterLineFighterNPC
- FishingMasterStructureHunterNPC
- FishingMasterDeepwaterVeteranNPC
- FishingMasterDriftAnglerNPC
- FishingMasterSignReaderNPC
- FishingMasterWeatherWatcherNPC
- FishingMasterTideReaderNPC
- FishingMasterSurfaceAnglerNPC
- FishingMasterLandingGuideNPC
- FishingMasterNatureGuideNPC
- FishingMasterGyosilNPC
- `locations/ManilloTraderNPC` and its playable regional instances
- `locations/ContextualItemShopNPC` and its inherited regional instances

Also covered by the shared adapter and QA: HarborLockbox, HarborRequestBoard,
RegionalChampionshipRegistrar and BeachGatheringNode3D (all six gathering
variants inherit the latter). Total **24 marker-bearing bases/derived types**.

Catalogue-only actors without authored markers need no migration. Travel-sign
labels and the bare, non-character Triple Triad trigger templates are not NPC
overhead markers and were not changed. Their grounded playable prop derivatives
(lockbox/board/registrar) are covered above.

## QA and rendered evidence

New `scripts/qa/world_marker_anchor_qa.gd` verifies all 24 types, single-visual
ownership, original controller paths, profile height, request states
available/accepted/ready/locked and the existing disabled-input visibility gate.
It runs three complete orbits, including both 0 and 360 degrees: 17 views at
22.5-degree intervals for Card Maker, Still Water Master and Crafter.

At every view it checks physical world/local anchor stability, unchanged actor
transform, projected icon directly above feet, camera-facing icon and original
text/color. The rendered variant additionally reads actual yellow glyph pixels
on a temporarily isolated background and verifies their horizontal center.
This catches a visually absent or laterally displaced glyph even if the Node3D
position assertion passes. Actual body-plus-icon screenshots are saved before
isolating the glyph; 51 views were captured, with representative captures
visually inspected.

The actual gameplay Card Maker patrol also runs for 24 sample frames. The request
icon must be visible, the actor must really move, the physical anchor must
follow, and the visible icon's screen position must match the same frame's
actor/camera projection. This cannot pass merely on collision-shape existence.

Results:

| QA | Result |
|---|---|
| Marker headless | **476/476**, exit 0 |
| Marker rendered Compatibility | **578/578**, exit 0; **6,409 actual glyph pixels** |
| Maximum horizontal projected icon drift | **0.00003052px** (floating-point rounding; threshold 0.01px) |
| Maximum live patrol follow error | **0.00004316px** (threshold 0.01px) |
| Grounding | **1084/1084** |
| Presentation tuning | **265/265** |
| NPC catalogue | **2589/2589** |
| Beach collision | **65 checks, 0 failures** |
| World actor collision | **96/96**, passive player displacement **0.0m** |
| Interaction | **93/93** |
| World locations | **586 checks, 0 failures** |
| Full fishing regression | **22950/22950** |
| Fight camera | **168/168** |
| Mobile presentation standard | **353/353** |
| `git diff --check` | PASS |

All regression processes exited 0. No GDScript errors or failed assertions
remain. Isolated rendered native runs emitted existing GLES shader-cache
`_save_to_cache: f.is_null()` filesystem diagnostics in both pre-fix and post-fix
runs; these were not swallowed or counted as passing assertions. The headless
regression logs had no `ERROR:` or `SCRIPT ERROR:` lines. Existing balance/QA
warnings remain unchanged. Native rendered verification does not substitute for
physical Safari acceptance.

Commands actually run from the project root with the installed Windows Godot
4.7.2 executable; native processes were launched hidden with Start-Process and
waited for exit. Logs are under `build/mobile-web/marker-*.log`.

```text
Godot --headless --path . --script scripts/qa/world_marker_anchor_qa.gd
Godot --path . --rendering-method gl_compatibility --script scripts/qa/world_marker_anchor_qa.gd -- --rendered --capture-dir=res://build/mobile-web/marker-qa-captures
Godot --headless --path . --script scripts/qa/world_grounding_standard_qa.gd
Godot --headless --path . --script scripts/qa/world_presentation_tuning_qa.gd -- --measurements=res://build/mobile-web/marker-presentation.json
Godot --headless --path . --script scripts/qa/npc_catalog_qa.gd
Godot --headless --path . --script scripts/qa/beach_collision_qa.gd
Godot --headless --path . --script scripts/qa/world_actor_collision_qa.gd
Godot --headless --path . --script scripts/qa/world_interaction_qa.gd
Godot --headless --path . --script scripts/qa/world_location_access_qa.gd
Godot --headless --path . --script scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions
Godot --headless --path . --script scripts/qa/mobile_presentation_standard_qa.gd
Godot --headless --path . --editor --import
git diff --check
```

Read-only diagnostic probes were used before/after the fix to record live
transforms and screenshots. Temporary probe scripts are removed; captures/logs
remain in ignored build storage. Production has no telemetry/debug overlay.

## Files changed and Web rebuild

- `scripts/world/world_marker_anchor.gd`: shared screen visual adapter with
  unchanged physical anchor and controller-state ownership.
- `scripts/world/ground_presentation.gd`: profile reapplication refreshes the
  marker anchor idempotently.
- `scripts/qa/world_marker_anchor_qa.gd` and its Godot-generated `.uid`.
- `docs/mobile/presentation_interaction_standard_v1.md`: current architecture.
- `docs/mobile/world_marker_runtime_anchor_audit_v1.md`: this report.
- Generated `export/index.html` and `export/index.pck`.

Ran the existing Linux/WSL build workflow:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1
```

Rebuild succeeded. Validated PCK **31,983,588 bytes**, internal `project.binary`
**9,944 bytes**, valid **ECFG** header. `index.js`/`index.wasm` remained unchanged.
HTTPS was not started or restarted. The Safari build is ready to refresh.

Physical follow-up: on iPhone, approach Card Maker, orbit L/R while stationary
and patrolling, then verify request states and dialogue. Also check one Master
and Crafter; icons should remain above the body, with no sideways orbit, duplicate
glyph or change to interactions. That physical-phone acceptance is the only
unperformed visual check; all requested automated suites and native rendered
camera-orbit checks completed.
