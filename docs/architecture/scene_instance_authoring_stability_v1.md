# Scene instance authoring stability v1

## Reproduced cause

The parent did not delete its Player or NPC instance. Saving the **child actor**
omitted its locally owned sprite, leaving an invisible physical actor in the
parent. Instance references, actor roots, colliders and root transforms survived.

The affected scenes instantiate `WorldGroundPresentation.tscn` and then add an
actor-owned Sprite3D/AnimatedSprite3D beneath its foreign `VisualAnchor`:

```
ActorRoot                         owner: actor scene
  GroundPresentation             instance of shared PackedScene
    VisualAnchor                 owned by shared PackedScene
      AnimatedSprite3D            owned by actor scene
```

The actor files lacked `[editable path="GroundPresentation"]`. Godot's editor
packing path did not descend into the locked instance to retain the locally
added sprite. Having the correct `sprite.owner` alone was insufficient.

An editor-hint packing probe reproduced the omission for Player, Still Water
Master and Card Maker. The Player's child count fell from 10 to 9; Still Water
Master from 10 to 9; Card Maker from 63 to 62. Their roots remained present. The
same probe retained the sprite when the declaration was enabled.

A subsequent **real Godot Compatibility editor** fixture used
`EditorInterface.open_scene_from_path`, `save_scene`, and
`reload_scene_from_path` in a disposable project. Removing the declarations in
that copy reproduced disappearing sprites in existing parent instances. Keeping
the declarations passed child saves, parent saves/hot reload, component saves,
shared shadow edits and cold parent reload. This is editor serialization evidence,
not an inference from runtime rendering.

## Fix

Added the nested-instance declaration to the 22 affected actor/base scenes. This
is stored in the reusable asset, not a instruction for designers to enable
Editable Children on every world instance. It does not change scene hierarchy,
ownership, transforms, collision, animation or shadow/profile values.

The catalogue's generated derived scenes already declared GroundPresentation
editable. Its reusable `NPCActor.tscn` base did not; saving that base could remove
the sprite inherited by the entire catalogue. The base is now corrected too.

The existing NPC ingestion script is an explicitly invoked file generator, not
an editor save hook. It already emits the declaration for derived catalogue
scenes. It was not invoked by Ctrl+S and was not the cause of this reproduction.

## Editor-time code and resources

- `GroundPresentation` is a tool preview component. It applies profile-derived
  sprite/visual-anchor and shadow state. It never deletes actors, changes owners
  or rewrites actor PackedScene references.
- Opening the unconfigured NPC base exposed a second error:
  `apply_frame()` tried to read a null SpriteFrames resource. Added checks for a
  valid sprite, assigned frames, existing animation and valid frame index. An
  empty authoring template is supported until its visual profile supplies frames.
- `CatalogueNPCActor` skips autonomous runtime setup and motion in the editor.
- `WorldBlobShadow` creates instance-specific mesh/material style and keeps its
  world transform flat; it does not free or replace actors. No redesign was needed.
- Marker anchoring and its temporary CanvasLayer/labels are runtime-only. The
  GroundPresentation installer explicitly skips editor execution, so these are
  not serialized into edited actor assets.
- Presentation profiles and shadow families remain shared external Resources.
  No local-to-scene conversion, UID regeneration, root rename/type change or
  destination-scene visual override was introduced.
- Existing fish-spot references contain an unrelated script UID typo
  (`b8cv7hluf70by` versus the script's `b8cv7h1uf70by`). Fresh isolated editor import
  reports path fallback. This is outside the actor-serialization fix; valid text
  paths still resolve, and these fish resources were not changed in this pass.

## Shared shadow authoring

Edit the shared family Resources directly:

- `data/presentation/shadows/player.tres`
- `data/presentation/shadows/humanoid_standard.tres`
- `data/presentation/shadows/humanoid_large.tres`

Width, depth, opacity and ground offset are family authority. Actor profiles
select the family and optional scale multiplier. Designers do not need to edit
or unpack WorldBlobShadow children to tune them. The real-editor fixture verifies
all four controls without changing parent actor transforms or bindings.

`humanoid_large` currently has no production profile assignment. The fixture
verifies it using a temporary profile override only in its disposable project;
it does not assign the family to a production NPC or change its final sizes.

Six grounding assertions still compared Player and five inherited outpost shadows
with the legacy `shadow_ground_lift` scalar. The current shared player family has
ground offset 0.05 while that legacy scalar remains 0.006. Corrected those two
assertion sites to use `resolved_shadow_family().ground_offset`. The checks still
compare against independent authored authority; no shadow value was changed.

## Future editing workflow

1. Open the reusable Player/NPC scene, edit its authored nodes, and save normally.
   Return to the parent: its instance and sprite should remain present.
2. For presentation tuning, open the actor's existing profile Resource:
   `data/presentation/player.tres`, the appropriate NPC presentation resource,
   or a catalogue entry's `data/npc/profiles/*.tres`. Catalogue actors also expose
   their `visual_profile`. GroundPresentation exposes `profile` in actor scenes.
3. Tune shared shadow family Resources rather than nested generated mesh state.
4. For a new manually authored actor that adds nodes beneath a nested shared
   presentation instance, preserve the declaration in the reusable actor scene.
   The serialization suite catches omission before the asset reaches gameplay.

No restriction on normal subscene editing is needed. The physical ActorRoot is
still feet/ground truth, and all parent placements remain unchanged.

## Regression fixtures and commands

`scripts/qa/scene_resource_integrity_qa.gd` packs/saves/reloads all actor families
off-tree, checks sprite preservation, source-file/UID preservation, transforms,
profiles and shadows, and reproduces the defect with declarations disabled only
in memory. It audits 66 actor scenes and passes 795/795 checks.

`tools/qa/run_scene_authoring_qa.py` prepares a disposable project below the ignored
`build/mobile-web/scene-authoring` directory. It copies source assets, never saves
into the production project, and enables the QA EditorPlugin only in that copy.
The plugin refuses to edit a project without the disposable marker file.

Example PowerShell commands from the project root:

```powershell
$python = "$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$godot = "$env:USERPROFILE\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe"
& $python tools/qa/run_scene_authoring_qa.py --directory build/mobile-web/scene-authoring/editor-new-run
& $godot --editor --path build/mobile-web/scene-authoring/editor-new-run --rendering-method gl_compatibility
& $godot --headless --path . --script scripts/qa/scene_resource_integrity_qa.gd
```

Use a fresh fixture directory for each run. Add `--negative-control` to the
preparation command to recreate the defect in the disposable copy; the editor
suite must then fail. The real editor suite passes 231/231 after the fix.
Reports contain before/after parent snapshots in `authoring-report.json`.

Other executed regressions (`--headless --path . --script scripts/qa/<suite>`):

| Suite | Result |
| --- | --- |
| `npc_catalog_qa.gd` | 2589/2589 |
| `world_grounding_standard_qa.gd` | 1084/1084 |
| `world_interaction_qa.gd` | 93/93 |
| `world_actor_collision_qa.gd` | 96/96; maximum passive player displacement 0.0 |
| `world_actor_policy_v2_qa.gd` | 200/200 |
| `world_location_access_qa.gd` | 586 checks, zero failures |
| `content_registration_qa.gd` | 2149/2149 |
| `runtime_lifecycle_qa.gd` | 1832/1832 |
| `runtime_lifecycle_qa.gd -- --mobile` | 1052/1052 |
| `session_contract_runner.gd` full fishing | 22950/22950; zero orphan nodes |
| Native/mobile lifecycle full fishing | 22950/22950 each |

The final real-editor run had no SCRIPT ERROR or ERROR output. The initial
editor-hint probe used a custom main loop and reported editor-dock shutdown
retention; it was removed. The permanent fixture uses the normal editor main loop.

## Production files changed

Only serialization declarations changed in these scenes:

```
actors/BeachCrafterNPC.tscn
actors/BeachFishingCritter.tscn
actors/BeachGatheringNode3D.tscn
actors/BeachMerchantNPC.tscn
actors/ExplorationPlayer_V2.tscn
actors/FishingCardMakerNPC.tscn
actors/FishingMasterCurrentReaderNPC.tscn
actors/FishingMasterDeepwaterVeteranNPC.tscn
actors/FishingMasterDepthReaderNPC.tscn
actors/FishingMasterDriftAnglerNPC.tscn
actors/FishingMasterGyosilNPC.tscn
actors/FishingMasterLandingGuideNPC.tscn
actors/FishingMasterLineFighterNPC.tscn
actors/FishingMasterNatureGuideNPC.tscn
actors/FishingMasterSignReaderNPC.tscn
actors/FishingMasterStillWaterNPC.tscn
actors/FishingMasterStructureHunterNPC.tscn
actors/FishingMasterSurfaceAnglerNPC.tscn
actors/FishingMasterTideReaderNPC.tscn
actors/FishingMasterWeatherWatcherNPC.tscn
actors/TripleTriadOpponentNPC.tscn
actors/npc/NPCActor.tscn
```

Other source changes: the empty-template guard in
`scripts/world/ground_presentation.gd`; the shared-family assertions in
`scripts/qa/world_grounding_standard_qa.gd`; two new QA scripts and their `.uid`
files; the disposable project preparation helper; this report. FishingTestScene,
shared GroundPresentation/WorldBlobShadow/marker scenes and all presentation
profile/family resources are unchanged.

Permanent QA/support files:

```
scripts/qa/scene_instance_authoring_editor_qa.gd
scripts/qa/scene_instance_authoring_editor_qa.gd.uid
scripts/qa/scene_resource_integrity_qa.gd
scripts/qa/scene_resource_integrity_qa.gd.uid
tools/qa/run_scene_authoring_qa.py
docs/architecture/scene_instance_authoring_stability_v1.md
```

`git diff --check` passed. The existing Linux Web helper rebuilt
`export/index.html` and `export/index.pck`; validated PCK size is 32,114,664 bytes,
with a 9,944-byte `project.binary` containing the ECFG header. HTTPS was not
restarted. No physical iPhone acceptance test was performed in this authoring pass.
