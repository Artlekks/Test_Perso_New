# Session Composition vs QA/Debug Separation v1

## Scope and audit coverage

Inspected desktop/mobile entry points, pending session acquisition, runtime
initialization, world binding, fishing scene bindings, Developer access,
F10/campaign QA overlays, Triple Triad composition, telemetry, explicit and
rendered runners, fixture cleanup and shared QA resource mutation. This is a
composition/ownership pass; content registration, gameplay, save schema, card
ownership, visual design and balance are unchanged.

Before this pass, debug-template startup synchronously ran the complete session
QA registry inside `FishingSessionServices.initialize()`. The session created
Developer Mode, campaign QA UI and crafting QA HUD; Fishing always preloaded and
created the regression-backed F10 controller and eagerly instantiated telemetry.
Triple Triad's packed scene required a debug menu, its composition eagerly
constructed QA/recording infrastructure, and backend QA defaulted ON at startup.
Five QA suites permanently forced the global Developer provider OFF.

```text
BEFORE
desktop Fishing / mobile-hosted Fishing
  -> FishingSessionServices.initialize
       runtime services + Developer + QA registry/suites/reports + QA HUD
  -> FishingDebugController -> regression harness / F10
  -> eager economy telemetry
TripleTriadGame -> required debug-menu scene + developer QA controller

AFTER
desktop Fishing / mobile-hosted Fishing
  -> SessionComposition.acquire (same singleton/pending-owner boundary)
       -> FishingSessionServices (runtime initialization and ownership only)
       -> WorldLocations autoload (existing authoritative world service)

optional debug playtest scene composition
  -> DevelopmentLayer under the session
       -> Developer access provider (default desktop OFF / mobile ON)
       -> campaign guide + crafting QA HUD
       -> scene-owned F10 and Triple Triad overlays
       -> economy telemetry only on explicit request

explicit QA runners
  -> SessionTestFixture (production scene + canonical session)
  -> FishingSessionQA.reports(session) (separate observer child)
       private QA resource graph + QA reports + suites
```

## Production-owned graph

`SessionComposition.acquire(tree)` preserves the former singleton/pending WeakRef
race protection. Fishing and optional scene composition now use the same public
acquisition seam. Initialization remains synchronous before safe deferred root
attachment. Readiness is published after composition completes, with an explicit
initializing guard; repeated scene acquisition does not reload saves.

The session still owns dialogue service/controller; progress and inventory;
catch repository; items catalogue, item inventory/facade/transactions; gathering
and crafting; cooking and prepared bait; Card Maker; trade/economy/access;
session modifiers, weather/current/tide; mastery and fish consumables; Manillo
ledger; unlocks/rewards/journal; save integrity; campaign progression and campaign
presentation; normal gathering feedback. Its existing runtime forwarding APIs
and integrity validation remain. WorldLocations remains the existing autoload.

Player, camera, fishing controller, Caster/Bait, Encounter, local gameplay menus,
NPCs and effects remain scene-owned. The recent bait ownership notifications,
instance-ID guards and shadow cleanup were not changed. Session loadout binding
now publishes `loadout_bound`, allowing optional views to observe it instead of
making production binding create a QA HUD.

`RuntimeAccessPolicy` is a neutral optional-provider seam. No provider means
normal authored access and no practice deck. Production consumers no longer
reference the Developer class or inspect the mobile harness. The Developer
implementation supplies access and transient practice cards through the seam;
its existing persistence restrictions remain.

## Development ownership and removal

`playable_location_scene.development_tools_enabled` explicitly controls the
debug-template playtest layer; it defaults true to preserve existing F10 tools
in this playtest project. Release templates skip it. A false value runs the same
production graph without Developer, F10, campaign QA UI or telemetry. There is
no automatic session QA run even when development tooling is enabled.

DevelopmentLayer creates the provider, guide and crafting HUD. F10 and card
overlays belong to their live scene; the layer records weak handles, prunes dead
handles on each scene mount, and releases only its installed overlays on removal.
Card QA/recording uses a neutral runtime observer until development composition
or an explicit QA command installs the actual tooling. The production card scene
no longer references `TripleTriadDebugMenu.tscn`; its backend works without that
node. Backend QA startup default is OFF. Explicit `run_backend_qa()` still works.

Economy telemetry is lazy. F10 receives a provider Callable, so its recording
button remains available without eagerly creating the recorder. Requesting
telemetry binds the canonical session and current runtime; recording observes
events rather than owning gameplay. Existing disconnect/stop behavior remains.

Campaign QA controller now releases its own guide even if mobile presentation
reparented it. Development removal likewise releases its own reparented crafting
HUD and card campaign menu. No global orphan scavenging was introduced.

## QA-owned graph and order

`FishingSessionQA` owns the extracted QA registry, reports and forwarding
commands. Explicit callers use `reports(session)`; repeated calls reuse one
observer and do not rerun the suite implicitly. Stability/fresh-save suites
receive the runtime and QA evidence separately. Runtime `is_ready()` does not
depend on QA dependency health or QA reports. Missing/broken QA can fail an
explicit QA run without becoming a production bootstrap prerequisite.

The adapter deep-duplicates QA catalogue inputs so legacy synthetic registration
cannot mutate the runtime's shared resources. It saves/restores the optional
provider state around the normal-state contracts. Five suites no longer
permanently force Developer OFF. This changes test composition, not content
registration or production progression.

`SessionTestFixture` instantiates actual production scenes, uses canonical
acquisition, records whether it created or borrowed the session, and releases
only its owned scene/session. It neither frees foreign nodes nor scavenges
orphans. `session_composition_separation_qa` alternates desktop/mobile fixture
order, verifies core-service equality, preserved defaults, removal, borrowed
ownership, shared-resource stability and strict shutdown.

`session_contract_runner` explicitly runs all extracted session QA, Triple Triad
backend QA and the full fishing regression, then requires zero orphan nodes.
Existing runners were migrated only where they read the moved reports or requested
the moved telemetry. Assertions were retained.

## Intentional differences and remaining debt

- Mobile remains a development wrapper: isolated save namespace, virtual input,
  portrait viewport/presentation hosting and Developer default ON. It instantiates
  the same gameplay scene/session core. CanvasLayer reparenting is presentation
  hosting; core service/data ownership stays canonical. Desktop Developer default
  remains OFF. The core graph comparison excludes CanvasLayer parent placement.
- P1 content registration remains deferred as requested: production mastery
  `ensure_technique` and existing runtime catalogue augmentation still exist. QA
  now uses private copies, but this pass does not migrate registration into data.
- P2: legacy runners still have scene-path lookups and some one-off detached
  fixtures. This pass adds a reusable canonical fixture and migrates report
  consumers, not every domain fixture. Strict existing teardown assertions remain.
- P2: Triple Triad retains historical QA profile/configuration fields and explicit
  debug command APIs for compatibility. Its actual QA scripts, recorder and menus
  are optional; a broader match-configuration API cleanup was not performed.
- The optional session QA registry still loads its dependencies as one explicit
  suite group. A broken member affects that explicit group, never runtime readiness.
- Physical Safari acceptance and a release-template execution remain unperformed.
  Native Compatibility mobile harness and validated Linux Web export are separate
  evidence; neither is described as physical phone acceptance.

## QA commands and results

Godot executable used: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`.
Commands below were executed via hidden `Start-Process -Wait -PassThru` with stdout
and stderr saved under ignored `build/mobile-web/composition-*.{stdout,stderr}`.

| Arguments after the executable | Result |
| --- | --- |
| `--headless --path . --script scripts/qa/session_composition_separation_qa.gd` | 102/102; 12 alternating host lifetimes plus cold/borrowed-session checks |
| `--headless --path . --script scripts/qa/session_contract_runner.gd` | PASS; Triple Triad 101/101; crafting 14/14 over 36 combinations; zero orphans |
| `--rendering-method gl_compatibility --path . --script scripts/qa/runtime_lifecycle_qa.gd` | Desktop lifecycle, six complete route loops; final result below |
| Same lifecycle command plus `-- --mobile` | Mobile lifecycle, six complete route loops; final result below |
| `--headless --path . --script scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions` | 168/168; full fishing 22950/22950 |
| `--headless --path . --script scripts/qa/world_location_access_qa.gd` | 586 checks, zero failures |
| `--headless --path . --script scripts/qa/world_interaction_qa.gd` | 93/93 |
| `--headless --path . --script scripts/qa/world_actor_policy_v2_qa.gd` | 200/200; maximum passive player displacement 0 |
| `--headless --path . --script scripts/qa/world_grounding_standard_qa.gd` | 1084/1084 |
| `--headless --path . --script scripts/qa/developer_playtest_qa.gd` | 89/89 |
| `--headless --path . --script scripts/qa/mobile_portrait_harness_qa.gd` | 182/182 |
| `--headless --path . --script scripts/qa/fishing_save_recovery_runner.gd` | 23/23; zero teardown orphans |
| `--headless --path . --script scripts/qa/deck_ownership_durability_qa.gd` | 91/91; expected corrupt-payload diagnostics |
| `--headless --path . --script scripts/qa/fish_shadow_bait_lifecycle_qa.gd` | 2562/2562; 336 casts, 24 transitions, 12 host lifetimes |
| `--headless --path . --script scripts/qa/runtime_economy_reconciliation_qa.gd` | 1002/1002 current invariant checks; assertion logic unchanged except explicit report lookup |
| `--headless --editor --path . --import` | Exit 0; no parse errors |
| `git diff --check` | Final result below |

Explicit session QA also passes dialogue 175/175, items 13/13, campaign 14/14,
Card Maker 10/10, mastery 64/64, Fight 24/24, Presentation 10/10, Stability 27/27
and Fresh Save 55/55. Economy guardrails remain **22/24** with both H12 ceiling
alerts. No prices, targets, balance values or save schema changed.

The initial lifecycle run failed its object-growth bound because the newly added
weak-handle arrays accumulated dead handles. Pruning at the development boundary
fixed that; bounds were not relaxed. A first core-graph assertion included the
normal feedback CanvasLayer that mobile intentionally reparents; it was corrected
to compare data/service ownership, with presentation hosting documented above.
Rendered runs retain existing GLES shader-cache write diagnostics. Deliberate
corrupt-save tests retain their diagnostic errors. No such messages are suppressed.

## Files changed

The complete final list and final lifecycle/build evidence are appended below.

## Final lifecycle evidence

Final rendered desktop **1832/1832**, mobile **1052/1052**. Across all six
complete route cycles: desktop structural nodes **2054**, resources **2202**,
connections **172**; mobile structural nodes **2268**, resources **2205**,
connections **42**. Both retain exactly one session service, four timers (one
active), zero surviving tweens and zero orphans. Ambient fish actors and real
owned specimens vary as expected and are accounted for by existing bounds.

Final contract and separation stderr contain zero script/engine errors. Rendered
lifecycle stderr contains zero script errors, with **64 desktop / 97 mobile**
existing GLES shader-cache write errors. These are reported, not suppressed.

## Complete changed/new file list

- `actors/TripleTriadGame.tscn`
- `docs/architecture/session_composition_separation_v1.md`
- `export/index.html`
- `export/index.pck`
- `scripts/developer_playtest_service.gd`
- `scripts/development/fishing_development_layer.gd`
- `scripts/development/fishing_development_layer.gd.uid`
- `scripts/fishing.gd`
- `scripts/fishing_debug_menu.gd`
- `scripts/fishing_economy_access.gd`
- `scripts/fishing_session_services.gd`
- `scripts/progression/playable_campaign_loop_qa.gd`
- `scripts/progression/playable_campaign_presentation_controller.gd`
- `scripts/progression/playable_campaign_presentation_qa.gd`
- `scripts/progression/playable_campaign_progression_director_qa.gd`
- `scripts/progression/playable_campaign_qa_controller.gd`
- `scripts/progression/playable_campaign_qa_guide_qa.gd`
- `scripts/qa/fishing_fight_camera_tracking_qa.gd`
- `scripts/qa/fishing_fresh_save_rehearsal_qa.gd`
- `scripts/qa/fishing_presentation_current_polish_qa.gd`
- `scripts/qa/fishing_session_qa.gd`
- `scripts/qa/fishing_session_qa.gd.uid`
- `scripts/qa/fishing_system_stability_qa.gd`
- `scripts/qa/fishing_torture_qa.gd`
- `scripts/qa/runtime_economy_reconciliation_qa.gd`
- `scripts/qa/runtime_economy_telemetry_qa.gd`
- `scripts/qa/runtime_lifecycle_qa.gd`
- `scripts/qa/session_composition_separation_qa.gd`
- `scripts/qa/session_composition_separation_qa.gd.uid`
- `scripts/qa/session_contract_runner.gd`
- `scripts/qa/session_contract_runner.gd.uid`
- `scripts/qa/session_test_fixture.gd`
- `scripts/qa/session_test_fixture.gd.uid`
- `scripts/qa/world_actor_collision_qa.gd`
- `scripts/qa/world_location_access_qa.gd`
- `scripts/runtime_access_policy.gd`
- `scripts/runtime_access_policy.gd.uid`
- `scripts/session_composition.gd`
- `scripts/session_composition.gd.uid`
- `scripts/triple_triad/triple_triad_composition_root.gd`
- `scripts/triple_triad/triple_triad_developer_tools_controller.gd`
- `scripts/triple_triad/triple_triad_game.gd`
- `scripts/triple_triad/triple_triad_runtime_observer.gd`
- `scripts/triple_triad/triple_triad_runtime_observer.gd.uid`
- `scripts/triple_triad/triple_triad_ui_flow_controller.gd`
- `scripts/world/playable_location_scene.gd`
- `scripts/world/world_location_service.gd`

Linux/WSL rebuild succeeded: PCK **32,056,792 bytes**; `project.binary`
**9,944 bytes**, valid **ECFG** header. `export/index.html` and `export/index.pck`
were published. HTTPS was not restarted. Final `git diff --check`: exit 0.
