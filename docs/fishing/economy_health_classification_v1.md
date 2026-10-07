# Economy health classification v1

Normal startup now gates Campaign Loop and Fresh Save on runtime/structural contracts, while retaining the original economy guardrail results. No price, ceiling, recipe, progression, save schema, or simulator transaction changed in this pass. Runtime playtest telemetry work is paused.

## Classification

Each simulator check carries a category. Structural checks are fatal. Only the two explicitly authored provisional checks, identified by `balanced_h12_cash_ceiling` and `sell_heavy_h12_cash_ceiling`, may become balance alerts. Missing/unknown classifications or an unrecognized provisional ID fail closed; classification is never inferred from a label or a current value.

`EconomyProgressionSimulator.classify_health()` separately validates route/provider metadata, acquisition sources, acquisition viability and completion in every profile, checkpoint availability, finite/nonnegative runtime counters, and cash/fish accounting. Campaign records that structural result and retains the unmodified aggregate summary and balance alerts. Fresh Save requires both the campaign contract and its structural economy result; existing stability/save-integrity assertions remain intact. Session initialization still calls `push_error` for hard failures, and calls `push_warning` for the two provisional alerts.

The explicit economy QA remains strict by default. Its optional `--structural-only` mode makes the structural gate independently runnable without changing any guardrail result.

## Balance truth preserved

- Reconciliation: **1029/1029 invariants**.
- Economy guardrails: **22/24**.
- Sell-heavy H12: **20975**, ceiling **15500** (failed).
- Balanced H12: **10537**, ceiling **8000** (failed).

Baseline reconciliation compares all 24 original labels, pass/fail results, values and targets, and every original checkpoint field. Only newly added classification metadata is excluded from the baseline equality comparison. Reporting ledgers from the preceding balance pass are preserved.

## Verification, 2026-10-07

Godot 4.7.2; commands ran against this project with disposable test userdata where startup/save access was needed. `A` below means `C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c`; `G` means `C:/Users/Alucard7th/Desktop/_Projects/Fishing Game/Godot_v4.7.2-stable_win64.exe`. These are command abbreviations, not project settings.

| Command (PowerShell invocation: `& G`, replacing the abbreviations) | Result |
| --- | --- |
| `G --headless --path . --quit-after 1800 --log-file A/health-final-classification.log --script res://scripts/qa/economy_health_classification_qa.gd` | 30/30, exit 0; injected hard failures still fail the Campaign gate |
| `G --headless --path . --quit-after 1800 --log-file A/health-final-reconciliation.log --script res://scripts/qa/runtime_economy_reconciliation_qa.gd -- --baseline=A/economy-balance-v1-before.json --report=A/health-economy-report.json` | 1029/1029, exit 0; 22/24 and both unmet H12 targets printed |
| `G --headless --path . --quit-after 1800 --log-file A/health-final-world.log --script res://scripts/qa/world_location_access_qa.gd` | World/location 573/573; architecture 566/566; full fishing 22950 checks, zero failures; exit 0 |
| `G --headless --path . --quit-after 1800 --log-file A/health-final-acquisition.log --script A/early_tackle_acquisition_qa_isolated.gd` | Acquisition 61/61, exit 0 |
| `G --headless --path . --quit-after 1800 --log-file A/health-economy-structural.log --script A/world_economy_access_qa_isolated.gd -- --structural-only` | 81/81, foundation 13/13, trade/access 208/208; 22/24 and two alerts visible; exit 0 |
| `G --headless --path . --quit-after 1800 --log-file A/health-economy-strict.log --script A/world_economy_access_qa_isolated.gd` | 80/81, expected exit 1 at unchanged strict aggregate balance gate; 22/24 and both alerts visible |
| `G --path . --quit-after 1800 --log-file A/health-rendered-cleanup.log --script A/health_rendered_startup.gd` | Actual `FishingTestScene_V2.tscn`, Windows/Vulkan rendering: Campaign 14/14, Fresh Save 55/55, structural PASS, two balance warnings; exit 0, no red errors |
| `git diff --check` | Passed |

The rendered launcher changes only test userdata and opens the actual Beach scene through normal scene initialization. Its first run reported test-fixture shutdown leaks; the rerun freed orphaned QA fixtures and completed without those leaks. Neither launcher is project production code. This confirms rendered startup health, not the visual correctness of gameplay presentation.

## Triple Triad warning

`triple_triad_backend_qa.gd::_test_public_facade_precomposition_guard()` (line 3449) deliberately calls `open_game_by_id()` on an uninitialized facade. The guard is expected, rejects the call, and already uses `push_warning` in `triple_triad_game.gd` (line 825). Rendered startup shows this exact QA call stack and Triple Triad 101/101. No Triple Triad file or guard was changed.

## Files in this pass

- `scripts/progression/economy_progression_simulator.gd`
- `scripts/progression/playable_campaign_loop_qa.gd`
- `scripts/fishing_session_services.gd`
- `scripts/qa/fishing_fresh_save_rehearsal_qa.gd`
- `scripts/qa/runtime_economy_reconciliation_qa.gd`
- `scripts/qa/world_economy_access_qa.gd`
- `scripts/qa/economy_health_classification_qa.gd` and its `.uid`
- This report.

The pre-existing untracked `first_10_hours_balance_v1.md` and prior simulator/reconciliation reporting changes were preserved. No telemetry, camera, or gameplay balance changes were added.
