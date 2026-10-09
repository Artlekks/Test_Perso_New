# FishShadowPresence freed-bait lifecycle fix v1

## Root cause and ownership

Caster owns the physical Bait child. Previously, FishShadowPresence discovered
that child through the global `bait` group and cached it until its next process
tick. Retrieval/cancellation freed the node between ticks. Tide/environment
updates could synchronously rebuild the ambient population before the presence
controller polled again. `_spawn_one_shadow()` then passed the stale reference
to the typed `FishShadowActor.set_ambient_bait(Node3D)` argument. Argument
validation rejected the freed instance before the actor's defensive guard ran.
Same-frame replacement could also discover the queued old bait through the group.

Caster now publishes `active_bait_changed` synchronously from its authoritative
property setter. Replacement, cancellation, retrieval, completed landing and
scene teardown all use that setter. Old gameplay signals are disconnected so a
late old-bait return/depth/snag event cannot operate on its successor.

Presence binds the Caster in its own gameplay scene, including the game inside
the mobile viewport. Ownership notifications replace production group polling.
Ambient bindings update immediately; a hooked shadow belonging to a replaced
cast releases its old target immediately. The existing intentional landing hold
keeps the same bait until the existing landing sequence releases it.

Caster, presence and individual shadow actors also subscribe to bait
`tree_exiting` for unexpected destruction. Callbacks bind instance IDs, never
the bait itself, and reject old-instance callbacks. Rebinding/teardown disconnects
those callbacks. Standalone QA scenes retain group discovery and a final validity
guard; this is not the production ownership mechanism.

Presence initialization is deferred but captures no bait. Population spawning
and environment rebuilds are synchronous. Pre-bite/fight shadow delays are
scalar process counters, not bait-capturing SceneTreeTimers or tweens; existing
clear/release paths invalidate them. No new timer, tween or controller is added.

## Reproduction and regression commands

Use Godot 4.7.2 from the project directory:

```powershell
$g = "$env:USERPROFILE\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe"
# Run each with Start-Process -WindowStyle Hidden -Wait -PassThru when scripting.
& $g --headless --path . --script scripts/qa/fish_shadow_bait_lifecycle_qa.gd
& $g --rendering-method gl_compatibility --path . --script scripts/qa/runtime_lifecycle_qa.gd
& $g --rendering-method gl_compatibility --path . --script scripts/qa/runtime_lifecycle_qa.gd -- --mobile
& $g --headless --path . --script scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions
git diff --check
```

The focused fixture disables presence polling and rebuilds the population after
every bait deletion: the original tide-before-poll ordering cannot hide behind a
fortunate next frame. It exercises 240 loop cycles, same-frame recasts, late old
signals, immediate free, missed opportunities, hooked replacement, intentional
landing holds, subsequent casts, 24 travels and 12 host startup/teardown lifetimes
(six desktop and six mobile). Travel during fishing remains correctly rejected;
the fixture also destroys a scene with a pending bait after releasing GameMode.
Save directories are isolated. Final teardown requires zero orphans.

Rendered native/mobile lifecycle QA additionally exercises six full route loops
and compares structural nodes, resources, signal connections, timers, tweens and
service ownership after warmup. Existing GLES shader-cache write diagnostics
are engine/environment output; they are neither suppressed nor counted as script
lifecycle success. Physical Safari acceptance remains separate from native
Compatibility harness stress.

The existing Linux/WSL mobile build helper validates the exported PCK before
publishing. It does not restart HTTPS or alter server configuration.

## Results (2026-10-09)

| QA | Result |
| --- | --- |
| Focused bait stress | 2560/2560; 336 casts; 240 loop cycles; 24 travels; 12 host lifetimes |
| Rendered desktop lifecycle | 1826/1826 |
| Rendered mobile harness lifecycle | 1052/1052 |
| Camera lifecycle/tracking | 168/168 |
| Full fishing regression | 22950/22950 |
| Cephalopod shadow presence | 18/18 |
| Fishing Fight | 24/24 |
| Fishing Presentation | 10/10 |
| Fishing System Stability | 27/27 |
| Godot editor import | Exit 0; no parse errors |
| git diff --check | Exit 0 |

Across all six settled route-loop samples: desktop structural nodes 2053,
resources 2260, connections 171; mobile structural nodes 2267, resources 2263,
connections 42. Both had four timers (one active), zero surviving tweens, one
session service and zero orphan nodes. Ambient population and genuinely acquired
fish specimens vary intentionally; those are accounted for by existing QA.

No script errors, freed-instance accesses, leaked-object or retained-resource
shutdown warnings occurred in final stress/lifecycle runs. Rendered runs still
emitted 46 desktop and 79 mobile GLES `_save_to_cache` write errors; these remain
explicit engine/environment diagnostics, not a claim of an entirely empty error
log. Known balance and defensive Triple Triad warnings remain unchanged.

Initial fixture assertions were corrected before final validation: GameMode's
setter alone is not retrieval; active fishing intentionally rejects travel;
environment/debug sync can reset the fixture's count override; a released hooked
actor may bind the new ambient bait, but must never retain the old cast or remain
hooked. None of these corrections weakens the production lifetime contract.

Linux/WSL Web rebuild completed successfully: published PCK 32,034,516 bytes;
`project.binary` 9,944 bytes with valid `ECFG` header. HTTPS was not restarted.
Refresh Safari to load the new build; physical iPhone stress was not performed
by this automated pass.
