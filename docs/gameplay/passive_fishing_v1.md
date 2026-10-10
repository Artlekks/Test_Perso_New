# Passive Fishing v1

The companion owns one runtime-only PassiveFishingController. It orchestrates
production fishing entry, cast confirmation, and Encounter's opportunity lease.
It owns no inventory, save, fish database, reward implementation or camera.

Passive is accepted at a legal fishing spot with selected owned rod and lure,
or from an existing AIM/IN_WATER fishing state. It refuses modal UI, incomplete
casts, fights and already-open bite opportunities. Automatic entry faces the
water without moving the player's physical feet. Cast confirmations pass through
the same animation callbacks and phase gates as normal confirm input.

Defaults exported on the controller:

| Setting | Default |
| --- | ---: |
| focus_seconds | 1200 (20 minutes) |
| opportunity_seconds | 300 (5 minutes) |
| cast_power | 0.65 |
| timer_entry_delay | 1 second after water settles |
| require_focus_confirmation | true |

After physical water entry, wait one second and display the editable focus timer
in the lower-middle gameplay area, above the power bar. Click to edit; `20`
means 20 minutes and `MM:SS` is supported. Enter or K confirms only in this
context. The clock does not start until confirmation. Then a monotonic wall-clock
timer schedules one opportunity at `focus_seconds + RNG[0, opportunity_seconds]`.
RNG can be seeded in QA; accelerated fixtures explicitly disable confirmation.
The ordinary encounter bite timer is stopped while the lease is owned, and stale
ordinary timer callbacks cannot bypass the lease. Ambient presentation continues.
When paused, delivery waits until gameplay resumes. No timer or readiness is saved.

Scheduled delivery uses the existing authored population, lure, depth and spatial
selection. It bypasses only ordinary polling probability/pre-bite delay. If there
is no eligible fish, Passive cancels with an explanation rather than fabricating
one. A successful opportunity uses the production bite lifecycle but leaves a
persistent hook-ready response: no short timeout, no automatic catch/reward.

Expanded shells show FISH READY; the tiny collapsed tab shows `!` with that tooltip.
Expand does not change activity.
Switch Active, then confirm normally to hook. The existing fight, landing, result
and reward/save pipeline resolves the opportunity. Switching Active early cancels
the passive schedule and resumes normal bite scheduling. I cancels Passive/ready
casts through the existing water-cast cancellation path. Travel, cast end and
shutdown release the weakly owned lease and runtime controller state.

Save/load uses existing production saves; focus time and practice orchestration
cannot become persistent inventory or rewards. Restart starts Active with no
pending passive opportunity. No operating-system notifications are implemented.

```powershell
& $Godot --path . --rendering-method gl_compatibility --script res://scripts/qa/passive_fishing_qa.gd
```

The accelerated fixture uses disposable saves, seeded timing, real cast
animations, persistent readiness, collapse/expand, production hook/reward/result,
repeated cancellation and travel invalidation. Its deterministic landing boundary
is not a substitute for manual fight-balance playtesting.
