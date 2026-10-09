# Mobile Presentation & Interaction Standard v1

## Shared presentation

`scripts/mobile/responsive_menu_surface.gd` is a reusable read-only presentation
adapter. Existing controllers still own the source labels, selected indices,
quotes, confirmation states, transactions and persistence. Declarative bindings
compose header, list, selected-detail, action and confirmation sections with the
same PanelContainer / VBoxContainer / ScrollContainer toolkit. No MerchantMobile,
CraftingMobile or CardMobile scenes/backends were created.

The portrait harness installs the adapter for FishingEconomyMenu (Merchant,
Buy/Sell and fish Trade), BeachCraftingMenu, FishingCardMakerMenu and
TripleTriadDeckSetup. Responsive rows wrap instead of squeezing independent tiny
columns; detail information follows the list. Selection automatically scrolls
into view; the gameplay right-hand gutter supports touch scrolling through the
existing shell input forwarding. Short gameplay viewports continue scrolling at
the same font size. Confirmation consumes the original controller input path.
Lazily created legacy feedback art is masked along with the original presentation;
its controller state and public node paths remain intact. Persistent menu layers
restore their original presentation when the harness exits.

Wide/desktop mode retains the existing authored multi-column composition, artwork,
mouse/keyboard paths and geometry. The adapter is installed by the optional mobile
host, not a second gameplay controller. Triple Triad match/board presentation and
fishing HUDs are not redesigned. Approved dialogue files/art/typography are untouched.

## Typography / skin

The normal responsive gameplay-menu minimum is **18 logical pixels**, using
`res://assets/fonts/BOF_Font_Refined.fnt`, matching approved dialogue body/speaker
text (18; dialogue choices remain their approved 16). This is not reduced to fit
content. Normal responsive text has scale 1, native bitmap modulation, no outline,
nearest texture filtering, and 3 logical pixels of line spacing. Development
metadata is exempt. Desktop legacy artwork/type sizes remain as authored.

The shared skin calls the already approved
`scripts/dialogue/dialogue_panel_style.gd` with `assets/ui/Panel.png`. It assembles
the authored tile atlas once per section into a StyleBoxTexture with 8px corners
and tiled edges/center, instead of stretching the complete atlas. The identical
panel language supplies headers, lists, details and actions. Unsupported bitmap
punctuation is converted only in presentation (em dash to hyphen, multiplication
to ASCII x, arrow to ->). Authored recipes/data are untouched.

## Portrait area / input

Target share changes from 60/40 to 69/31, with a minimum controls height of 236
reference CSS/logical pixels. For iPhone 13 Pro reference 390x844, top inset 47,
bottom inset 34, the safe area is 390x763:

| | Before | After |
|---|---:|---:|
| Gameplay resolution | 640x751 | 640x863 |
| Gameplay display | 390x457.640625 | 390x525.890625 |
| Controls height | 305.359375 | 237.109375 |
| Effective share | 59.978% / 40.022% | 68.924% / 31.076% |

Existing horizontal camera projection/HUD anchoring adapt through the existing
harness paths. No camera tracking values or fishing logic are changed. Safe area
and home clearance remain. A/B hit rectangles are 74.1px, C 58.5px, and shoulders /
MENU / SELECT / START have >=44px targets at this reference size, all nonoverlapping.
The joystick radius remains its original 56; mappings/deadzone/analog logic remain.
The existing development-status reserved control region is retained.

Mobile START continues emitting Space for existing debug/cast behavior. Deck setup
alone accepts Space while `mobile_start_enabled` and calls `_try_confirm_deck()`.
It displays **START : PLAY** when the normal five-card/cost contract is ready.
Desktop Enter remains valid; desktop Space remains unchanged. Narrow collection
navigation moves one row at a time through the same controller selection method.
The temporary DEV hand still creates no real ownership/save/stakes changes.

## World markers

`scripts/world/world_marker_anchor.gd` creates one root-owned **WorldMarkerAnchor**
for each GroundPresentation actor that has PromptLabel3D or RequestMarker.
`WorldActorPresentationProfile.marker_height` (default 0.72 world units) supplies
height. Its world-aligned transform follows the physical actor root. The runtime
anchor audit found that a correctly fixed world-height point still has lateral
perspective parallax against a billboarded body in the authored exploration
camera. The user explicitly selected screen-space icon placement while retaining
the fixed physical anchor.

The anchor now owns `MarkerCanvas` and one camera-facing 2D visual per source.
Icons project vertically above the physical feet using the profile's marker
height and scale from the source pixel size at the actor's depth. Only this
screen presentation responds to the camera. Physical anchors, actors, sprites,
shadows and camera transforms are unchanged. Existing PromptLabel3D/RequestMarker
paths remain state sources; their 3D labels use render layer 0 so there is no
duplicate icon. Fonts, text, outline, colors and request/modal visibility come
from those sources. No destination-scene placement supplies the rendered height.
Fishing rod/bait screen-space helpers are deliberately unaffected.

`world_marker_anchor_qa.gd` inventories all 24 marker-bearing actor bases and
derived traders, checks request states and real Card Maker patrol movement, and
runs complete 360-degree orbits around Card Maker, Still Water Master and Crafter.
Rendered runs inspect actual glyph pixels at every 22.5-degree step, supplementing
the physical transform checks. See `world_marker_runtime_anchor_audit_v1.md` for
the before/after evidence, complete actor list and commands. Physical iPhone
acceptance is still separate from native rendered execution.

## Shadow families / exact tuning surface

**To resize all standard humanoid shadows, edit only:**
`data/presentation/shadows/humanoid_standard.tres`.
Change **width and depth** together for a round footprint. For example .22 -> .26
on both applies to every standard humanoid, independently of player/critter families.
Remote/runtime Resource edits propagate through GroundPresentation; no F10 resource
writer was added. Use the ordinary Godot Resource Inspector and catalogue preview.

| Family resource in data/presentation/shadows/ | Width | Depth | Opacity | Ground offset |
|---|---:|---:|---:|---:|
| player.tres | .18 | .18 | .65 | .006 |
| humanoid_standard.tres | .22 | .22 | .65 | .006 |
| humanoid_large.tres | .28 | .28 | .65 | .006 |
| humanoid_small.tres | .18 | .18 | .65 | .006 |
| critter.tres | .10 | .10 | .60 | .006 |
| ground_prop.tres | .10 | .10 | .40 | .006 |
| item.tres | .07 | .07 | .35 | .004 |

Every reusable presentation/NPC profile selects `shadow_family` and optional
`shadow_scale_multiplier` (default 1.0). Standard humanoids use the standard family;
player is independent; crabs, small catalogue creatures and the small bird use
critter. Large/small humanoid families are explicit opt-in choices; new roles/art
are not guessed. **No production NPC-specific multiplier was added**. Existing
small item/prop footprints retain data-level multipliers where needed (.05/.07,
.08/.07, .18/.10); these are reusable profiles, never destination transforms.

Existing non-character footprint preservation multipliers:

| Reusable prop/item profile | Multiplier |
|---|---:|
| coastalherb / driftwood / ironscrap / seaweed | 1.14285714 |
| seaglass / shell | 0.71428571 |
| harborlockbox | 1.6 |
| regionalchampionshipregistrar (ground-prop category) | 1.8 |

`world_shadow_families.gd` is the registry; old ingestion names humanoid and
small_creature resolve to standard/critter for compatibility. The ingestion builder
writes the new family IDs without duplicating an inherited profile property.
Legacy scalar size fields are storage-only compatibility data, hidden from the
normal Inspector and not authoritative in production. Optional baseline-footprint
QA now translates its preview sizes into a profile multiplier.

ActorRoot -> GroundPresentation -> ShadowAnchor -> WorldBlobShadow is preserved;
the latter remains world-aligned and independent of sprite animation/facing.
Existing shadow texture/material/grounding/collision are unchanged. Smoke remains
disabled. No destination scene or actor transform was edited.

## Actual QA results / commands

Windows QA uses the installed Godot 4.7.2 executable:

```powershell
$godot = "$env:USERPROFILE\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe"
$qa = Start-Process -FilePath $godot -ArgumentList '--headless','--path','.', '--script','res://scripts/qa/<suite>.gd','--log-file','build/<suite>.log' -WindowStyle Hidden -Wait -PassThru
$qa.ExitCode
```

Rendered suite omits --headless and appends `-- --rendered`. Editor import used
`--headless --path . --editor --import --quit`. Logs/captures are preserved outside
the project under the Codex visualization artifact directory for this pass.

| Suite / invocation | Actual result |
|---|---|
| mobile_presentation_standard_qa -- --rendered, final | 372/372; 5 real mobile menus, 4 desktop menu captures, 3 actors/8-angle orbits, actual patrol |
| mobile_portrait_harness_qa, final | 182/182; safe layout, >=44px nonoverlap, analog/multitouch/HUD/catch/input |
| developer_playtest_qa | 89/89; actual A removes/reselects fifth card, actual START starts match, save-byte purity |
| mobile_web_parity_qa, actual Linux Web/DOM TouchEvents | 36/36; fifth card removal/reselection, START, C/A, SELECT/F10, travel; disposable localhost origin |
| world_interaction_qa | 93/93 |
| world_actor_collision_qa | 96/96; passive player displacement 0, epsilon .00001 |
| npc_catalog_qa | 2375/2375 |
| world_presentation_tuning_qa | 265/265 |
| world_grounding_standard_qa | 1013/1025; same 12 known gathering-baseline failures |
| world_economy_access_qa -- --structural-only | 81/81; Foundation 13/13, Economy/Trade/Full-Access groups 208/208 |
| world_economy_access_qa without structural-only | 80/81; explicit balance failure retained, simulator 22/24 |
| fishing_fight_camera_tracking_qa -- --regressions | camera 120/120; full fishing 22950/22950 |
| Startup backend checks in full fishing | Triple Triad 101/101, crafting 14/14 (36 combinations), Card Maker 10/10, Fight 24/24, Presentation 10/10, Stability 27/27, Fresh Save 55/55 |
| Final editor import | exit 0, no script/parse errors |
| git diff --check | PASS |

Known balance alerts remain H12 sell-heavy 20975 >15500 and balanced 10537 >8000.
No values or severity rules changed. Native rendered isolated QA still logs
shader-cache `f.is_null()` write errors; these are not suppressed. Expected defensive
Triple Triad startup-QA warnings retain their guard. No new script/runtime errors
were present in final QA. Physical Safari readability/usability acceptance is pending.

## Web delivery / acceptance

Final rebuild command (existing exporter; HTTPS never restarted):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1
```

Linux build validated **31,791,844-byte PCK**, with **9,944-byte project.binary**,
valid **ECFG** header, matching index basename. Refresh the existing Safari HTTPS
address. Production main scene/preset, certificates, server and save handling were
not changed. Disposable browser QA modified only the Linux QA mirror main-scene
setting, restored it, and served localhost:8064; that temporary server/tab were closed.

On iPhone: inspect Merchant and fish trade, scroll their selected owned/required
information, inspect Crafting/Card Crafting, and build a temporary DEV deck through
the final card then START. Check A/B/C/L/R/SELECT/START comfort with the smaller
control region, including while fishing/catch-result HUDs are active. Orbit Card
Maker during walking/turning/dialogue to judge marker/feet appearance. Families
and profile multipliers have runtime invariant coverage; final visual preference
still belongs to your physical-phone review.

Complete modified/new source list: `presentation_interaction_standard_v1_files.txt`.
