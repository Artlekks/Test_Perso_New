# NPC Catalogue Batch Ingestion v1 + Developer Playtest UX v1.1

## Inventory and coverage

The source folder contains **28 PNG sheets**, all already present at the start
of this pass. The full inventory contains **35 NPC sheets / 61 character sheets**
(26 player sheets). Existing seven catalogue actors and their SpriteFrames remain
in place. The batch adds **29 entries**, for **36 total**: the blue and orange
bearded variants share a single source PNG but have separate profiles/scenes.

All 28 sources have proven guide-bounded frame extraction. Ten visually reviewed
five-view sheets have standing N/NE/E/SE/S groups; nine have NE/SE walking strips
at 8 FPS and the small bird has two flapping strips instead. No west/rear art is
fabricated; the existing nearest-direction resolver provides missing coverage.
Eighteen sheets remain **NEEDS_REVIEW** for direction/action semantics and timing.
Their individually extracted static poses are available in the catalogue, not
misrepresented as finished walking animations. No sheets failed frame extraction.

See `batch_coverage.json` for each source's exact status and `asset_inventory.json`
for source dimensions, resource references, frame regions and animation FPS.
Special Teleporter Guardian / three Master role mappings remain **UNCONFIRMED**.
More than one supplied sheet fits the descriptions, and file order does not prove
the original reference-image order. No special-role tags or lore were guessed.

The generated assets reuse NPCActor, GroundPresentation, family colliders and
WorldBlobShadow. Roots remain at physical feet, Y=0; destination placement is X/Z
only. Per-animation sheet-space stance metadata handles transparent padding.
Source PNG pixels are untouched, filtering remains nearest, guide borders are
excluded, and no art is regenerated. Existing production world NPCs are not moved
or replaced by the library additions.

## Library and ingestion

Catalogue: `data/npc/catalog/npc_catalog.tres`.
Ready-to-drag scenes: `actors/npc/catalog/NPC_<id>.tscn`.
Profiles: `data/npc/profiles/<id>.tres`.
New SpriteFrames: `data/npc/frames/<id>.tres`.
Preview: `actors/npc/NPC_Catalogue_Preview.tscn` (F6).

Preview controls: Q/E orbit, +/- zoom, Tab inspect next actor closely, Space walk,
I idle, R cycle available authored poses/actions, C toggle collider overlays.
Every entry is instantiated in the preview. Mixed sheets keep their static pose
fallback when no reviewed walking group exists.

Future batch command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\npc\build_npc_catalog.ps1
```

The scanner discovers source sheets and creates reviewable `.npc.json` manifests.
Top/bottom and both side guides prove cells; small authored gaps in guide lines
are accepted only with >90% boundary coverage and no interior guide pixels.
Unknown directions/actions remain individually named poses. Grouping is restricted
to explicitly reviewed source layouts, not inferred for future lookalike grids.
Existing manifests are preserved. Review animation names, direction map, timing,
stance and family metadata in the sidecar, set `batch_generated` false when
reviewed, then rerun the builder. `scan_source_batch.py --refresh-generated`
refreshes only explicitly generated manifests. Variant sheets can use an
`entries` array in one sidecar. IDs are validated and duplicate IDs rejected.

## Developer menu and temporary deck

F10 opens PLAYTEST with **Developer Mode: ON/OFF** first, followed by Travel To,
explicit fishing/card/wallet loadouts, economy recording and other debug pages.
Mobile A activates/toggles; direction/stick moves selection; Travel To opens an
authored destination submenu, A requests normal travel, B backs out before closing
the menu. SELECT opens/closes F10; START still switches fishing QA pages.
Desktop keyboard value controls and existing fishing QA shortcuts remain.
Clear Test Loadout remains omitted because safely rolling back an explicit grant
must not remove legitimate earnings.

The card service supplies five unique, legitimate starter cards deterministically
through the existing acquisition policy only when the real owned cards cannot
form a rank/budget-legal five-card deck. Real legal ownership uses the normal
deck/profile workflow. The fallback lives only in the deck setup's runtime array;
real collection backends/snapshots are never filled with borrowed ownership.
The screen labels it **DEV Deck / Test Cards (temporary)**. Normal deck count,
rank, budget and match controls still apply.

Borrowed-deck profile saves/sanitization are disabled; no borrowed IDs are written
to saved decks. The match uses the existing engine/dealing/movement/AI controls.
Its result is a practice result without persistent stakes/rewards/progression.
DEV OFF closes a borrowed session immediately and clears its effective cards.
Mode subscription is bound after readiness and checked at match entry, because
the shared developer service may be created after the card UI composes.
Explicit Grant Card Test Loadout remains separately guarded by isolated-save
authorization and now grants the actual policy starter set instead of catalog
indices that might not form a legal low-rank deck.

Native QA compares all save-file bytes before/after temporary match entry,
confirmation, result, close and DEV OFF; real owned cards stay empty throughout.
Desktop default OFF / mobile harness default ON and normal progression rules are
preserved. Actual normal-deck matches retain their existing persistence path.

## Responsive presentation

One shared authored-coordinate fitting/scrolling helper serves the mobile economy,
crafting, Card Maker, card/deck, fishing/card debug and campaign guide windows.
It measures the content against the actual gameplay viewport, centers fitting
content with eight logical pixels of vertical padding, and exposes a scrollbar
when the viewport is too short. Fonts and internal node paths are preserved.
Mouse wheel and a 64-logical-pixel right touch gutter scroll oversized content;
the harness forwards those gameplay-region touches to its SubViewport only while
a scrolling modal is visible. Virtual A/B/C and fishing controls are unchanged.
Desktop F10 uses the same helper so its 580px panel is reachable in a 480px window.
Persistent-layer layout and helper nodes are restored/removed when leaving the
harness.

Only explicitly tagged development status layers relocate: the red economy REC
label moves to the unused right control region at x=78%, y=60%, wrapping within
21% width/height. It does not intersect A/B/C or SELECT/START at the reference
layout. Legitimate location artwork, fishing HUD and yellow DEV indicator retain
their established positions. No general HUD relocation or global font reduction.

## Verification actually run

Godot 4.7.2 Windows, isolated save fixtures. Standard command (wait for process
completion; PowerShell GUI executables can otherwise return before QA finishes):

```powershell
$qa = Start-Process -FilePath "$env:USERPROFILE\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe" -ArgumentList '--headless','--path','.', '--script','res://scripts/qa/<suite>.gd','--log-file','build/<suite>.log' -WindowStyle Hidden -Wait -PassThru
$qa.ExitCode
```

Rendered suites replace `--headless` with `--rendering-method gl_compatibility`
and append `-- --rendered` (mobile also `--capture-dir=build/mobile-batch-captures`).

| Suite | Actual result |
|---|---|
| npc_catalog_qa (rendered) | 2375/2375; every frame, directional map, grounding, families, real player/actor collision, all preview entries; four orbit captures and close-up |
| developer_playtest_qa | 87/87; actual C/A card entry, match start, temporary result, DEV OFF during reopened match, all-file save-byte equality, real ownership unchanged, F10 A/B/START/SELECT and actual travel |
| mobile_portrait_harness_qa | 198/198 headless; 212/212 rendered, all seven window captures, short-height fit/scroll and actual touch gutter dispatch |
| mobile_web_parity_qa | 34/34 in Linux Web export using actual DOM TouchEvents on disposable localhost origin; temporary match and A/B/SELECT/travel |
| world_interaction_qa | 93/93 |
| world_actor_collision_qa | 96/96; passive player displacement 0, epsilon .00001 |
| world_location_access_qa | 573 checks, zero failures |
| world_presentation_tuning_qa | 265/265 |
| world_grounding_standard_qa | 1013/1025; unchanged known 12 gathering-area baseline differences |
| fishing_fight_camera_tracking_qa -- --regressions | 120/120 camera; full fishing 22950/22950, rerun after desktop fitter change |
| Full fishing startup QA | Triple Triad 101/101, Card Maker 10/10, crafting 14/14 (36 combinations), Campaign Loop/Director/Guide/Presentation 14/14,14/14,8/8,9/9 with DEV OFF; Fresh Save 55/55, Fight 24/24, Presentation 10/10, Stability 27/27 |
| runtime_economy_reconciliation_qa | 1002/1002 current committed invariants |
| economy_health_classification_qa | 30/30; dedicated guardrails remain 22/24 |
| git diff --check | PASS |

Known balance alerts remain: sell-heavy H12 wallet 20975 >15500 and balanced H12
10537 >8000. Prices/ceilings were not changed. Grounding baseline was already
proven identical on untouched HEAD in the previous pass. Isolated native mobile
rendering still emits shader-cache `f.is_null()` write errors; these are reported,
not suppressed. Browser/native test acceptance does not substitute for physical
iPhone acceptance. New role tags and 18 mixed-sheet animation/direction mappings
remain explicitly incomplete.

## Web delivery

The final served export uses the existing validated WSL/Linux workflow:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1
```

The staged PCK is validated before replacing export/index.*. No HTTPS server
restart, server/certificate edits or manual PCK patching. Final artifact values
and complete changed-file list are recorded alongside this report after build.

Final production PCK: **31,763,104 bytes**; `project.binary`: **9,944 bytes**, valid
**ECFG** header. HTML/JS/WASM/PCK basename remains `index`. The existing HTTPS
listener stayed active on port 8060. Refresh Safari; no server restart is needed.
Complete source changes: `batch_files_changed.txt`.
