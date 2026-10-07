# Runtime Economy Playtest Telemetry v1

Measurement only. The structural/balance classification is preserved. No prices, ceilings, recipes, encounter rates, fishing controls/balance, progression, world access, or save schema changed.

## Player workflow

In a Godot debug build, enter fishing and wait for normal aiming, then open the existing **F10** fishing debug menu. Click **Start Economy Playtest Recording**, or select the last row with W/S or controller up/down and use A/D or controller left/right. Close the debug menu with F10 and play normally. The small red **REC Economy playtest** label stays visible while recording, including during travel and menus.

To finish, return to aiming (reel back normally if necessary), open F10, and use **Stop Recording & Save Report**. The same control changes its wording while active. Mouse clicks and keyboard/controller row selection are supported; key-repeat does not repeatedly toggle recording. No permanent hotkey was added.

The persistent session service also exposes debug tooling:

```gdscript
var telemetry = get_node("/root/FishingSessionServices").get_economy_playtest_telemetry()
telemetry.start_recording()
telemetry.stop_recording()
# If disk writing fails, the previous report remains in memory:
telemetry.retry_save_report()
```

No automatic recording at startup. Disabled telemetry has no event connections, no processing, and no telemetry output directory/files. Recording survives location changes and reconnects to the new Fishing runtime. Stop disconnects all observers. On graceful recorder removal an active session gets a best-effort stop/report; a forced process kill cannot preserve the in-memory session.

## Reports

Reports are separate from saves, under **`user://playtest_telemetry/`**:

- `session_<timestamp>_<monotonic counter>.json`: raw events, attempts, economy ledger, species aggregates, opening/ending snapshots and measurement notes.
- `session_<timestamp>_<monotonic counter>_summary.json`: session summary, top five species by actual sale income, Salmon/Squid statistics, acquisition times.

The absolute raw-report path prints in Godot's output on successful stop and appears in the menu button tooltip. Use Godot's Open User Data Folder to find the directory for this project. Test reports use isolated userdata, not your normal save directory.

## Architecture and measurement definitions

`economy_playtest_recorder.gd` is a plain data recorder driven by a monotonic clock. `runtime_economy_telemetry.gd` is a persistent session child that observes existing committed service signals, encounter events and runtime activity. Only the successful cast-commit path has a small observational hook. It never writes inventory/progression, changes resources, calls RNG or alters gameplay input ownership. The recorder is available only in debug builds.

Captured session data includes real elapsed time, UTC start/end, opening/ending wallet/location, progression/unlock snapshots, owned equipment and selected gear. Activity uses exclusive categories: active fishing, waiting/in-water, fight, world movement, travel, shop/trade UI (including Card Maker), crafting, Triple Triad, and other. Menus take precedence over fishing; unknown/idle/paused/debug activity is other. Sampling boundaries have frame precision. Travel is observed through the existing transitioning flag and location bind/unbind signals; no world-access behavior changes.

Each successful cast records location, zone path, authored population species, rod/lure, prepared bait context and debug-forced-fish status. Bite opportunities record encountered species. Hook signals record species, size, size band, king state, points/score tier and canonical sell value. Attempts finish as landed, escaped, failed or partial, with reason, duration and fight duration. The physical bait return that begins landing ends the fight clock but does not prematurely classify the catch as failed. The later fish-caught event ends the landed attempt. Repeated cleanup cannot count it twice. Missed bites remain per-encounter events; one cast may have several bites.

Recording that begins during an existing fight marks it partial, rather than fabricating the earlier encounter/hook. Its observed landing can still be counted, but full-fight averages, hook/landing rates and completed-attempt rates exclude the missing portion where applicable. No-bite reel-back is a failed attempt, not an escaped hooked fish. Stopping mid-attempt produces partial, not a fake failure.

Species aggregates include encounter/hook/landing/loss/missed-bite counts, observed hook/landing rates, full observed fight averages, rod usage, landed canonical value, actual sale income and active fishing minutes. Species active minutes mean **population exposure**: the full fishing time in zones whose authored population includes that species. These denominators overlap and include waiting; they do not claim to identify the player's intended target. Separate identified-target seconds cover only the known selected fish. Consequently Salmon zenny/minute is actual Salmon sale income divided by Salmon population-exposure minutes. Sales may include fish owned before recording; consumed specimen metadata remains in raw sale details. This is evidence for a focused human playtest, not a claim that Salmon is already balanced.

Martian Squid reports first/second observed landing timestamps, active exposure seconds to the second, encounter/hook counts at each landing and the session attempt number needed to reach each. `time_to_two_seconds` remains null if the recording has fewer than two landings. These are recording-relative measurements, not invented full-campaign timings.

The nine acquisition IDs match the requested spine: Baby Frog, Bamboo Rod, Tail, Crab, Floater, Popper, Angling Rod, Silver Top, Hanger. Already-owned items have `pre_existing: true` and a null acquisition time. First committed new ownership records elapsed time, location, committed wallet and telemetry landed count; shop/trade/craft completion annotates the actual authored source. Other ownership paths stay explicitly `inventory_commit` rather than guessing a merchant.

## Economy ledger

The inventory's committed `zenny_changed` notification captures wallet-before/after once. Subsequent sale/purchase/Card Maker completion enriches that same entry with source, source ID and the result payload; it does not debit/credit a second time. Fish trades and current beach crafting record zero-wallet-delta material transactions. Existing crafting consumes materials and has no zenny fee.

Other wallet changes are retained with their actual delta and debug call stack as `unclassified_wallet_change`; they are counted and visible rather than invented as a sale or suppressed. A nonzero ending-wallet reconciliation error sets `ledger_reconciled: false` and warns while retaining raw evidence. Both raw wallet notifications and transaction annotations appear as distinct event kinds; the economy ledger contains one monetary delta.

## Verification — 2026-10-07

Godot 4.7.2. All startup/save tests used disposable userdata. Telemetry QA checks actual committed sale, purchase, fish-trade and Card Maker operations, plus the runtime landing callbacks and a real Beach-to-Ocean scene transition. Its 90-second example uses a manually advanced test clock and synthetic fishing outcomes; it is not a human balance measurement.

| QA | Result |
| --- | --- |
| Telemetry lifecycle/data/runtime integration | **91/91**, exit 0 |
| Full fishing regression | **22950/22950**, exit 0 |
| Fight camera | **120/120**, exit 0 |
| Fishing Fight / Presentation / Stability | **24/24**, **10/10**, **27/27** |
| Structural economy access | **81/81**, exit 0; foundation **13/13**, trade/access **208/208** |
| Acquisition | **61/61**, exit 0 |
| Reconciliation | **1029/1029**, exit 0; original values and guardrails preserved against pre-balance baseline |
| Campaign / Director / Guide / Presentation | **14/14**, **14/14**, **8/8**, **9/9** |
| Fresh Save | **55/55** |
| Health classification | **30/30**, exit 0 |
| Explicit strict economy QA | **80/81**, expected exit 1; **22/24** and both unchanged H12 cash failures visible |
| Rendered Beach startup/menu recording | Windows/Vulkan; start/stop and JSON writing succeeded; no red startup errors or teardown leaks |
| `git diff --check` | Passed |

Save/RNG checks compare existing top-level save bytes, inventory transaction snapshot and progression snapshot before/after idle start/stop, and the next seeded global RNG result. The only new output is telemetry JSON. Independent recording outputs and retained in-memory reports are tested. The rendered start/stop screenshots were inspected for button/indicator visibility; this is not a long human economy playthrough.

Commands used (PowerShell, from the project): let `G` denote the actual Godot executable at `C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe`, and `A` denote the artifact directory `C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c`. Replace those abbreviations and invoke with `&`.

```text
G --headless --path . --quit-after 1800 --log-file A/telemetry-qa-final.log --script res://scripts/qa/runtime_economy_telemetry_qa.gd
G --headless --path . --quit-after 1800 --log-file A/telemetry-fishing-final.log --script res://scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions
G --headless --path . --quit-after 1800 --log-file A/telemetry-economy-final.log --script A/world_economy_access_qa_isolated.gd -- --structural-only
G --headless --path . --quit-after 1800 --log-file A/telemetry-economy-strict-final.log --script A/world_economy_access_qa_isolated.gd
G --headless --path . --quit-after 1800 --log-file A/telemetry-acquisition-final.log --script A/early_tackle_acquisition_qa_isolated.gd
G --headless --path . --quit-after 1800 --log-file A/telemetry-reconciliation-final.log --script res://scripts/qa/runtime_economy_reconciliation_qa.gd -- --baseline=A/economy-balance-v1-before.json --report=A/telemetry-economy-report.json
G --headless --path . --quit-after 1800 --log-file A/telemetry-health-final.log --script res://scripts/qa/economy_health_classification_qa.gd
G --path . --quit-after 1800 --log-file A/telemetry-rendered.log --script A/telemetry_rendered_check.gd
git diff --check
```

## Example output

Copied artifacts: `A/telemetry-synthetic-example.json` and `A/telemetry-synthetic-example-summary.json`.

The deliberately synthetic 90-second fixture has 80 active fishing seconds (88.9%), five completed casts plus one partial, five encounters, four hooks, three landings and two failed/escaped attempts. It earns 1000z and spends 200z: `100 + 1000 - 200 = 900`, reconciliation error zero. Baby Frog is pre-existing; Bamboo Rod is acquired at 40 seconds. Salmon has three encounters, two hooks, one landing and one escape. Squid landings occur at 60 and 70 seconds, on session attempts 3 and 4. These accelerated rates are QA arithmetic, not gameplay balance evidence.

## Files changed in this pass

- `scripts/fishing.gd`: debug binding and successful-cast observation hook.
- `scripts/fishing_session_services.gd`: lazy session-owned debug recorder accessor.
- `scripts/fishing_debug_menu.gd`: start/stop row/button using existing menu input.
- New `scripts/telemetry/economy_playtest_recorder.gd` and `.uid`.
- New `scripts/telemetry/runtime_economy_telemetry.gd` and `.uid`.
- New `scripts/qa/runtime_economy_telemetry_qa.gd` and `.uid`.
- This document.

Prior uncommitted balance reporting and health-classification changes remain preserved; they are not additional telemetry edits. No production QA or structural failure handling was removed or weakened.
