# Focused dialogue and Web parity pass

## Presentation

Ocean Spot 2 uses BOF_Font_Refined.fnt, font size 12, nearest filtering,
white modulation, and a parent scale of 1.8. There is no custom text material,
outline, or shadow treatment. Its bitmap atlas already contains shaded grey
glyph colors. Dialogue used the same atlas/filter but multiplied its glyphs by
very dark colors, producing the heavier appearance.

Dialogue speaker/body/choices now use white modulation to preserve those native
atlas colors. Existing sizes 18/18/16, wrapping, scrolling and Panel.png remain.
The footer label and all footer-hint generation are removed; content retains
14 logical pixels of bottom padding. Fishing HUD/layout/controls were untouched.

## Actual exported route diagnosis

In the failing exported browser runtime, before instantiating gameplay:

```
WEB PREBOOT ROUTES: []
WEB ROUTE EVIDENCE: os=Web id=beach routes=[]
sign_destination=wyndia_ocean_outpost label=Route unavailable
```

The source beach.tres contained its authored destination. The binary-converted
export cache beach.res contained property names but omitted both destination
and economy-provider path strings. Thus this was exported resource metadata
loss, not a mobile progression rule or a route UI fallback. The deeper cause
inside Godot's converter/cache was not established.

Set export/convert_text_resources_to_binary=false in project.godot so exports
preserve authored text metadata and the existing raw-file scene audits. No
destination, unlock, save, price or economy source was changed. This also
restored structural startup QA that relies on those resources/audits.

After rebuilding and testing the actual WASM/PCK in a disposable loopback
browser origin:

```
WEB PREBOOT ROUTES: ["wyndia_ocean_outpost"]
WEB ROUTE EVIDENCE: os=Web id=beach routes=["wyndia_ocean_outpost"]
sign_destination=wyndia_ocean_outpost
MOBILE WEB PARITY QA: 19/19
```

Canonical travel succeeded through Ocean, Lake, River and Chiqua inside the
mobile host. An explicit blank inventory still has zero unlocked destinations.
The QA entry scene is dormant; the shipping mobile entry remains
MobilePortraitHarness.tscn. To run exported parity QA, temporarily select
MobileWebParityQA.tscn as the mobile main scene, export to an isolated directory,
restore the main scene, and serve it from a disposable loopback origin. Never
run this acquisition/travel fixture against a player's normal browser origin.

## C input

No faulty C production mapping was reproduced. Native rendered and exported
Web tests use real ScreenTouch events: C -> KEY_C -> existing shell input
forwarding -> WorldInteractionRouter -> TripleTriadOpponentNPC -> conversation;
A confirms and opens the actual match. The authored starter card-case unlock,
real interaction Area and facing requirements remain in force.

C is the desktop world card-challenge shortcut; desktop in-match rotation is
R. No speculative C-to-R remap or alternate match-opening flow was introduced.
The reported C failure remains unconfirmed outside the tested unlocked,
in-range, facing-NPC context. A clarification about the failing context was
requested. Export metadata preservation fixes the demonstrated Web discrepancy;
it does not prove the particular reported C failure had the same cause.

## Verification

Godot executable: C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe

Commands run from the project (Windows GUI executable was awaited using
Start-Process -WindowStyle Hidden -Wait):

| Godot arguments / command | Actual result |
| --- | --- |
| --headless --path . --script res://scripts/qa/mobile_portrait_harness_qa.gd | 157/157 |
| --path . --rendering-method gl_compatibility --max-fps 60 --fixed-fps 60 --quit-after 8000 --script res://scripts/qa/mobile_portrait_harness_qa.gd -- --rendered --capture-dir=<artifact-directory> | 164/164; seven rendered captures |
| --path . --rendering-method gl_compatibility --script res://scripts/qa/dialogue_readability_qa.gd -- --rendered --capture-dir=<artifact-directory> | 125/125; dialogue captures inspected |
| --headless --path . --script res://scripts/qa/world_location_access_qa.gd | 573 checks, zero failures |
| --headless --path . --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions | camera 120/120; full fishing 22950/22950 |
| --headless --path . res://actors/mobile/MobileWebParityQA.tscn | 19/19 |
| Actual browser Web export of MobileWebParityQA.tscn | 19/19; touch C, card match and real hosted travel |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1 | normal export/index.html build succeeded |
| git diff --check | passed |

Fishing Fight 24/24, Presentation 10/10, Stability 27/27, Campaign Loop 14/14,
Fresh Save 55/55 and Triple Triad backend 101/101 passed. Known provisional
H12 economy alerts remain 22/24; no guardrails changed. Native rendered runs
also emitted existing GLES shader-cache write errors; these are not described
as a clean engine log. Actual Web startup had green structural reports and
the existing balance/precomposition warnings.

Rendered captures were inspected at the 390x844 portrait reference size.
No physical iPhone test was performed in this pass. Safari visual confirmation
and the user's specific remaining C failure context still require confirmation.
The temporary localhost QA server/tab were closed; the existing HTTPS LAN
server remained running on port 8060, process 2964.
