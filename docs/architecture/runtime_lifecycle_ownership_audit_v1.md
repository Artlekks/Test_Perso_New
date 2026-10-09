# Runtime Lifecycle & Resource Ownership Audit v1

Date: 2026-10-09. Engine: installed Godot 4.7.2. No presentation tuning, gameplay balance, input, camera feel, or art changes.

## Historical warning: reproduced, not dismissed

An isolated archive of commit `7c8e4b8` reproduced the original mobile harness result exactly: **163/163 assertions**, followed by **87 leaked ObjectDB instances, eight detached Nodes, and 76 resources still in use at exit**. Verbose output identifies the retained fish atlas, fish/behavior/spot resources, environmental catalogues, mastery resources and their scripts. These are retained through leaked project-created QA services, not a Web-only/editor baseline.

Applying **only** the current cleanup changes to `beach_crafting_qa.gd`, `fishing_tide_sense_qa.gd` and `fishing_read_fish_sign_qa.gd` in that historical copy retains **163/163** and removes the leaked-instance/resource shutdown warnings. This controlled comparison establishes causality.

Evidence is in ignored `build/mobile-web/history-mobile.{stdout,stderr}` and `history-mobile-fixed.{stdout,stderr}`. Godot's log file alone did not capture its late shutdown diagnostic; redirected stdout/stderr were necessary.

## Defects and responsible-boundary fixes

| Finding | Evidence / responsible function | Fix |
|---|---|---|
| Eight startup QA fixture Nodes leaked | `BeachCraftingQA._test_inventory_atomicity`: one gathering inventory. `FishingTideSenseQA.run`: tide, current, environment, mastery and unlock Nodes. `FishingReadFishSignQA.run`: mastery and unlock Nodes. All were `.new()` detached Nodes without an owner or teardown. | Each creator releases its own exact fixtures after its existing assertions. Consumers are released before dependencies. Assertions/values unchanged. |
| Ten additional full-regression fixtures leaked | Strict `FishingRegressionHarness.run_all()` passes **22950/22950**, yet leaves ten Nodes and **341 resources** at shutdown. `_test_economy_contract`: progress/trade; `_test_player_economy_access_and_save_integrity`: inventory, progress, trade, economy, modifiers, consumables, access and integrity. | Explicit local teardown in those two creator functions. No generic orphan scavenger or suppressed warning. |
| Duplicate session initialization race | Two same-frame `_get_or_create_session_services()` requests returned different Nodes and attached two persistent service trees. The first tree was invisible to the second request until its deferred `add_child`. | Publish a pending **WeakRef** on the SceneTree root before initialization. Reuse it during deferred attachment. Session `_ready` removes the pending metadata once attached. The same reproducer now returns one instance. |
| Persistent services held invalid scene loadout pointers | Session `active_loadout`, crafting `_active_loadout`, crafting QA HUD `_loadout` and save-integrity `loadout` refer to the departing scene's `FishingLoadout`. Node references do not prevent destruction, but later method calls on these references are unsafe. | `FishingLoadout._exit_tree` invokes session `unbind_loadout(self)`. The session clears all four bindings only if this exact loadout still owns the binding, protecting a replacement scene's binding. |
| Mobile development CanvasLayer restored to null viewport | Rendered harness exit reports `Cannot set viewport to nullptr` at `MobilePortraitHarness._exit_tree`. The persistent development layer outlives the gameplay SubViewport. | Restore `original_parent.get_viewport()` before reparenting to the persistent owner. No layout/style changes. |
| Conversation survives destruction of its source | A live `DialogueNPCBridge` starts a non-cancellable line; freeing it leaves `DialogueService.is_active() == true` and `SceneTree.paused == true`. | Bridge `_exit_tree` disconnects first, clears pending action state, then force-closes only its matching active conversation with reason `source_removed`. Reproducer becomes `active=false, paused=false`. An unrelated bridge cannot close another conversation. |
| Detached splash on unavailable scene root | `Fishing._spawn_surface_splash` instantiated the effect before testing whether `GameplaySceneRoot.resolve` returned an owner. Its early return could abandon the instance. Static failure-path finding. | Resolve/validate the owner before instantiation. Normal effect behavior unchanged. |
| Invalid dialogue scene root abandoned | `DialogueController._ensure_view` rejected a wrong-type instantiated root without freeing it. Static failure-path finding; current authored scene is valid. | Release that exact rejected instance while retaining the error. |

The strict lifecycle fixture tests pending landing callbacks and camera tween cancellation after owner destruction, as well as final scene loadout release. The two defensive invalid-resource/absent-owner branches above were inspected statically; malformed scene resources were not injected into the production project.

## Coverage checklist

| System | Ownership inspected | Runtime evidence |
|---|---|---|
| FishingSessionServices | One session Node at SceneTree root; service children; initialization, pending attachment and scene loadout bindings | Same-frame race test; service instance identity across 48 transitions; final teardown |
| Fishing / Encounter / Caster | Bait is Caster child; encounter timers belong to scene; landing delay callbacks are owned by fishing receiver | Repeated entry/exit, production cast creation, water entry, retrieve, hook and landing; destroy during pending landing |
| Camera rig | `Node.create_tween` binds lifetime to rig; tracker references scene-local target | Destroyed rig's outstanding 30-second tween becomes invalid; existing camera QA unchanged |
| Mobile portrait harness | Game dies with viewport; persistent session layers temporarily reparent and return; weak binding map; input released on exit | Rendered Compatibility stress, viewport restoration and dialogue owner checks; existing touch harness QA |
| Developer Playtest Mode / F10 | Session-owned service/indicator; scene-owned debug controller/menu; pause ownership | Repeated toggles and modal open/close, travel, standalone Developer QA |
| Dialogue | Session flow/controller/view; source-local bridges and explicit disconnection | Repeated open/advance/close; destruction of non-cancellable source; unrelated-source protection |
| Triple Triad | Scene-owned backend/controllers/deck/reward views and AI timer; natural signal receiver cleanup; reward sequences use sequence IDs | Repeated real match start/close with five actually owned starter cards; backend QA and Developer QA match/result coverage |
| Card Maker | Scene-owned actor/bridge/menu; session-owned crafting service | Repeated menu lifetime; travel; loadout release and catalogue/interaction/collision regressions |
| Crafting | Session-owned records/runtime lure cache, scene menu, loadout boundary | Repeated menu open/close; startup crafting assertions; strict fixture inventory cleanup |
| Merchants/traders | Scene-owned actors/menus; access context clears on close/exit | Repeated merchant open/close; route provider/access and interaction QA |
| Travel / WorldLocations | Autoload; current scene WeakRef; location resources cached; session progression subscriptions reconnect safely | Full route cycle six times; previous scene WeakRefs resolve null; session identity preserved |
| NPC catalogue / previews | Catalogue is authored Resource cache; preview owns generated actors/collider previews/labels/materials | Three complete preview creation/destruction cycles; catalogue QA |
| World markers | Actor-owned anchor/CanvasLayer/Labels; source labels remain state inputs; no session registry | Released with all 48 previous scene roots; catalogue/grounding/interaction regressions |
| Telemetry / recording | Session telemetry; weak runtime/scene/menu references; explicit connection buckets; indicator child | Six isolated recordings spanning travel; stop clears both signal buckets; no change to recording/economy behavior |
| Ripple | Bait-owned node and animation signal; keyed shared frame cache; hide on completion/miss | Cast/return destroys bait subtree; cache count stabilizes; existing presentation tests |
| Splash / fish shadows | Scene-owned effects self-free; fish presence owns bounded ambient population; animation-finished/expiry cleanup | Real hook/landing/travel releases effects; ambient population separated from structural counts |
| Temporary UI | Scene menus or deliberate session views; node-bound tweens; pause ownership | Repeated modal cycles and teardown; persistent dialogue view restored to controller |
| Signals | Persistent service subscriptions counted; all callable receivers checked valid; source bridges/telemetry explicitly disconnect | Counts remain stable at canonical Beach boundary; no invalid receivers |
| Timers/tweens | Scene Timer nodes; receiver-bound SceneTreeTimer continuations; node-bound tweens | Stable Timer count; no settled tweens; pending callback cannot commit after free |

No claim is made that `Timer` enumeration includes `SceneTreeTimer` objects: those are not Nodes and have no public global enumeration here. Their relevant production continuations are exercised directly, including free-before-timeout.

## Stress fixture and legitimate retention

`scripts/qa/runtime_lifecycle_qa.gd` uses a unique disposable userdata directory. It never frees unknown orphans to make its result pass. It runs six cycles of:

`Beach -> Ocean -> Lake -> River -> Chiqua -> River -> Lake -> Ocean -> Beach`

This is **48 actual route transitions**, 54 scene activity batches, 66 fishing enter/exit pairs, 24 production cast/return cycles (12 retrieves, 12 hook/land cycles), 12 actual card match start/close cycles where the authored opponent exists, three preview teardown cycles, six telemetry recordings, plus callback/tween cancellation tests and the full 22950-check regression with a strict no-orphan gate.

DEV grants route access only in this isolated fixture; production gates, economy amounts and saves are unchanged. The starter card case is acquired through its existing service in the disposable save so progression does not add a salvage bottle midway through otherwise comparable samples.

Expected retention during a live session:

- Authored Resource/Script/PackedScene/texture/font catalogues and shared ripple/splash frame caches load once and stabilize. Preview warmup intentionally loads catalogue art not otherwise visible at Beach.
- Location autoload and the one persistent session/service tree survive travel by design.
- Every landed fish adds one `FishingFishSpecimen` RefCounted to the real inventory. Twelve specimens at the final sample are owned loot, not orphan resources.
- Ambient fish-shadow Nodes vary with species, segmentation and lifetime. Their bounded, scene-owned population must not be mistaken for structural growth.
- Telemetry intentionally retains the latest report and accumulates evidence during an active recording. Stop disconnects sources; session destruction releases its recorder/report ownership.

Total object counts are reported raw and compared after subtracting the measured ambient Nodes and actual owned specimen count. Structural Nodes/resources/connections must remain fixed; the object comparison allows four engine/transient bookkeeping objects. Shutdown stdout/stderr are inspected independently of these live-session tolerances.

Final rendered Compatibility measurements across all six canonical Beach samples:

| Metric | Desktop | Mobile harness |
|---|---|---|
| Structural live Nodes | **2053 -> 2053**, fixed every cycle | **2267 -> 2267**, fixed every cycle |
| Raw live Nodes | 2067–2076 | 2275–2289 |
| Cached live Resources | **2258 -> 2258**, fixed | **2261 -> 2261**, fixed |
| Raw Object count | 8189–8200 | 8692–8703 |
| Objects minus measured ambient Nodes and owned specimens | 8171–8173 | 8675–8677 |
| Persistent signal connections / invalid receivers | **171 / 0**, fixed | **42 / 0**, fixed |
| Session service trees | **1**, same identity | **1**, same identity |
| Timer Nodes / active Timer Nodes | **4 / 1**, fixed | **4 / 1**, fixed |
| Settled processed tweens | **0** | **0** |
| Orphan Nodes | **0** every cycle and after full regression | **0** every cycle and after full regression |
| Owned landed specimens | 2 -> 12 (intentional inventory growth) | 2 -> 12 (intentional inventory growth) |

Final shutdown streams contain **no leaked-instance, retained-resource or SCRIPT ERROR diagnostics**. Rendered QA still emits the classified GLES cache-write errors. Historical before/after orphan figures are eight -> zero for startup QA and ten -> zero for the detached full regression; its 341-resource shutdown retention also disappears.

Evidence: `build/mobile-web/lifecycle-complete-native.{log,stdout,stderr}`, `lifecycle-complete-mobile.{log,stdout,stderr}`, `lifecycle-native.json`, `lifecycle-mobile.json` and `regression-owner-{before,after}.{log,stdout,stderr}`. JSON contains all six raw measurements, not just extrema.

## Shader-cache classification

GLES `Condition f.is_null()` at `_save_to_cache` is an **engine cache/filesystem environment issue caused by the isolated QA bootstrap changing userdata after renderer initialization**, not a failed project shader or a project-owned resource leak. The rendered QA profile lacks the cache directories created during initial renderer setup. Configuring a disposable userdata profile in the project **before startup** produces cache directories and no `_save_to_cache` diagnostics under the same renderer and permission conditions.

Godot's [GLES cache implementation](https://github.com/godotengine/godot/blob/master/drivers/gles3/shader_gles3.cpp) initializes cache directories earlier, then `_save_to_cache` opens the cached path for writing and emits this condition when FileAccess fails. This engine code also excludes the GLES binary cache on Web. Source is the current upstream implementation; installed-engine observations/log line numbers are separately recorded in the run logs.

The cache diagnostics remain visible. No engine warning suppression, global rendering-setting change, or project shader change was made. Historical Vulkan diagnostics were **not reproduced** in this Compatibility-only pass; their exact backend-specific classification remains incomplete.

## Verification commands

Commands below were launched with `Start-Process -WindowStyle Hidden -Wait -PassThru`, installed executable `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`, `--path .`, and separate `--log-file build/mobile-web/...` files. Lifecycle/historical probes also redirect stdout/stderr to capture late exit reports.

| Arguments / suite | Observed result |
|---|---|
| `--headless --script scripts/qa/runtime_lifecycle_qa.gd` | Earlier complete stress (before nested strict regression addition): 1820/1820; zero project orphans |
| `--rendering-method gl_compatibility --verbose --script scripts/qa/runtime_lifecycle_qa.gd` | **1826/1826**, exit 0; nested full fishing **22950/22950**, no orphan scavenging |
| Same, followed by `-- --mobile` | **1052/1052**, exit 0; nested full fishing **22950/22950**, no orphan scavenging |
| `--headless --script scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions` | Camera 168/168; full fishing **22950/22950**; Fight 24/24, Presentation 10/10, Stability 27/27 |
| `--headless --script scripts/qa/world_location_access_qa.gd -- --architecture-only` | **579 checks, zero failures**, including normal acquisition/travel/provider gates |
| `--headless --script scripts/qa/world_interaction_qa.gd` | **93/93** |
| `--headless --script scripts/qa/world_actor_collision_qa.gd` | **96/96**, passive displacement 0.0, epsilon 0.00001 |
| `--headless --script scripts/qa/world_grounding_standard_qa.gd` | **1084/1084** |
| `--headless --script scripts/qa/world_presentation_tuning_qa.gd` | **265/265** |
| `--headless --script scripts/qa/npc_catalog_qa.gd` | **2589/2589** |
| `--headless --script scripts/qa/mobile_portrait_harness_qa.gd` | **182/182**, rerun after final runtime changes |
| `--headless --script scripts/qa/developer_playtest_qa.gd` | **89/89**, rerun after final runtime changes |
| Session bootstrap `BeachCraftingQA.run` | **14/14**, 36 recipe combinations; assertions preserved |
| Scene bootstrap `TripleTriadGame.run_backend_qa` | **101/101**; repeated live match start/close additionally exercised |
| `git diff --check` | **PASS**, no whitespace errors |
| `& tools/mobile/build_mobile_playtest.ps1` | Linux/WSL build successful; PCK **31,996,640 bytes**, project.binary **9,944 bytes**, **ECFG**, 39 settings, checksum validated; existing HTTPS server untouched |

The expected Triple Triad precomposition warning originates in `_test_public_facade_precomposition_guard`, which deliberately requests a match before composing its test facade. It is not a gameplay caller or leaked match. Dedicated provisional H12 balance warnings remain unchanged.

## Files changed in this audit

- `scripts/beach_crafting_qa.gd`
- `scripts/fishing_tide_sense_qa.gd`
- `scripts/fishing_read_fish_sign_qa.gd`
- `scripts/fishing_regression_harness.gd`
- `scripts/fishing.gd`
- `scripts/fishing_session_services.gd`
- `scripts/fishing_loadout.gd`
- `scripts/dialogue/dialogue_controller.gd`
- `scripts/dialogue/dialogue_npc_bridge.gd`
- `scripts/mobile/mobile_portrait_harness.gd`
- `scripts/qa/runtime_lifecycle_qa.gd` (new)
- `scripts/qa/runtime_lifecycle_qa.gd.uid` (new)
- `docs/architecture/runtime_lifecycle_ownership_audit_v1.md` (new)
- `export/index.html` (generated by Linux exporter)
- `export/index.pck` (generated by Linux exporter)

`index.js` and `index.wasm` were rebuilt/copied by the helper but have unchanged Git content. No server, certificate, economy-balance, shadow, marker, art or camera-tuning files were changed.

## Explicit limits

- **Web/Safari object/resource census and Web shutdown stress: incomplete/not run.** The actual native mobile portrait harness was tested with rendered Compatibility. Linux Web export integrity was validated; that is not browser lifetime proof.
- **Vulkan-specific shader-cache reproduction: incomplete/not run.** GLES root cause is supported by rendered control execution.
- No visual correctness claims. No presentation values/layouts/markers/shadows were adjusted.
- Existing unrelated marker changes were already present when this audit began and were committed separately as `6f3929c` while this audit was running.
