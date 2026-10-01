# Triple Triad Backend Freeze Audit — v1.0.0

**Source of truth:** `fishing_game_clean_candidate_FRESH (8).zip`
**Audit date:** 2026-09-30
**Target:** current Godot 4.7 project / Triple Triad minigame backend
**Principles:** modularity, scalability, performance
**Scope:** Triple Triad runtime, rules, AI, card data, collections, deck persistence, opponent persistence, acquisition, progression, transaction recovery, save integrity, public state API, QA harness, and fishing-menu lock integration.

## Freeze status

The backend is suitable to freeze as **v1.0.0** for the upcoming visual/UI integration. The audit intentionally does **not** finalize authored card rarity/tier balance, character strength, NPC native pools, or the new UI. Those are content/presentation decisions and the backend now exposes data-driven hooks for them.

No card-layout scene was edited during this audit. `actors/TripleTriadCardView.tscn` was hash-compared against the uploaded project and remained unchanged.

## Correctness / integrity fixes

- Backend startup now **fails closed** if a protected save is corrupt and has no valid backup. It no longer continues into collection/progression initialization where a damaged save could be overwritten with defaults.
- Static authored data is validated **before any persistent save mutation**. Card catalog, opponent registry, region/rule configuration, acquisition policy, starter-deck viability, and progression catalog are checked first.
- Card-transfer recovery is guarded against a **second transaction while a journal is pending**. A partially saved player↔NPC transfer remains idempotent and blocks another transfer until recovery is complete.
- Missing primary save + valid `.bak` now restores from backup. Corrupt primary + no valid backup is reported as unrecoverable instead of silently reseeding.
- Player deck integrity now validates ownership, uniqueness, hand size, point budget **and Duel Rank/card-use policy**.
- Deck persistence now has an explicit save schema version.
- Card-catalog budget hand generation no longer returns an over-budget “fallback” hand. If a legal hand cannot be built, it fails explicitly.
- NPC stolen-card rematches now treat stolen cards as **hard recovery priorities** (up to the five-card hand). If necessary, the NPC’s effective match budget is temporarily raised to keep the stolen card recoverable instead of silently omitting it.
- Opponent availability is centralized in the registry and `open_game_by_id()` now enforces enabled state and required player Duel Rank.
- The acquisition policy’s `allow_duplicate_ownership` flag is now actually enforced by the player collection backend.
- `Same Wall` and `Elemental` remain future rules, but enabling either now fails validation explicitly. The runtime will no longer silently advertise an enabled rule it does not resolve.

## Modularity changes

- Runtime backend now exposes `BACKEND_VERSION = "1.0.0"` and the public snapshot layer exposes `API_SCHEMA_VERSION = 1`.
- The public state API remains the boundary intended for the redesigned UI. UI code does not need to know collection save paths, progression internals, opponent files, acquisition history, or encounter-record layout.
- Opponent gating logic lives in `TripleTriadOpponentRegistry` instead of being duplicated by the game controller and state API.
- Backend QA is dynamically loaded only when requested/debug-enabled. Shipping gameplay no longer has a hard preload dependency on the regression harness.
- Acquisition history and per-opponent encounter records now keep authoritative runtime state in memory and expose query methods without rereading save files.
- Current large `TripleTriadGame` and `TripleTriadDeckSetup` scripts are intentionally **not aggressively split during this freeze**. They are application/presentation controllers tied to the current UI. Refactoring them immediately before a UI replacement would add regression risk without improving the backend domain model. The new UI should consume the public API and can introduce smaller presentation controllers where useful.

## Scalability changes

- Card lookup by stable `card_id` is indexed and becomes O(1) after one lazy catalog index build instead of linearly scanning the whole roster on every lookup.
- NPC legal-deck selection now uses a memoized bounded solver instead of exponential include/skip recursion. Complexity is effectively bounded by card count × hand size × point budget for this five-card game.
- State snapshots cache deck/opponent ConfigFiles and computed snapshots per invalidation cycle instead of performing repeated disk reads for every panel/card/opponent query.
- Acquisition history and encounter records are loaded once and queried from memory.
- The current 179-card roster is unchanged, but the architecture is now appropriate for hundreds of cards and many opponents without turning UI refreshes into repeated file I/O.

## Performance review

No Triple Triad backend work runs per-frame. Disk I/O is limited to lifecycle/state mutations (save, transaction, checkpoint) or one-time cached snapshot loading. Hot UI query paths are memory-backed after cache construction. Card rendering/animations remain presentation concerns and were not changed by this backend audit.

## Regression QA

The pure backend QA harness now contains **16 deterministic tests**:

1. Basic directional capture
2. Same capture
3. Plus capture
4. Same → Combo chain
5. Rotate once per player
6. Regional rank bonus
7. Match-state invariant after placement
8. AI prefers an available capture when capture weight dominates
9. Card Duel Rank gate
10. Opponent registry duplicate-ID guard
11. Board rows do not wrap across flat-array boundaries
12. `preview_move()` does not mutate live match state
13. Plus → Combo chain
14. Region can disable Rotate
15. Opponent availability unlocks at the required Duel Rank
16. Unimplemented rule toggles are rejected rather than silently running

In a debug Godot build, the expected startup message is:

`TripleTriad QA: 16/16 backend tests passed.`

## Static audit completed

- 29 Triple Triad scripts inspected.
- 281 `res://` preload/load/resource references checked; no missing static dependency found (dynamic format-string paths excluded from literal dependency checking).
- Duplicate top-level function names checked.
- Delimiter balance checked across all Triple Triad scripts.
- `git diff --check` passed for whitespace errors.
- `card_stats.json` parsed successfully: schema 2, 179 unique cards, valid point/rank ranges.
- Current catalog card count matches the 179-card authored roster.
- Every persistent Triple Triad subsystem now has an explicit save version.
- Sacred `TripleTriadCardView.tscn` verified unchanged against the uploaded source project.
- The previous typed-array QA regression (`registry.opponents = [...]`) is absent.
- Runtime gameplay no longer hard-preloads the QA harness.

**Limitation:** no Godot executable is installed in this execution environment, so this is a source/static architecture audit rather than a real Godot 4.7 runtime launch. The first local validation step after applying the patch should be to open the project and confirm the debug QA reports `16/16`.

## Intentionally deferred content decisions

These are ready for data authoring later and are **not backend gaps**:

- final card tiers/rarities (Bronze / Silver / Gold / Mythic or whatever naming you settle on)
- hero/boss/named-character tier assignments
- final top/right/bottom/left values and card point costs
- per-card Duel Rank requirements
- authored NPC native collections and preferred decks
- final player rank names/thresholds/rewards
- final UI, colors, card borders, tier visuals, animations and information hierarchy

## Game-design decisions to settle before shipping

These do not block UI integration, but they should be consciously decided rather than left accidental:

1. **Abandon / forfeit policy.** The current match UI can leave a match before the wager resolves, including from the result phase. If losing a card is meant to be mandatory, abandoning should eventually either be disabled after the deal or treated as a forfeit with a defined stake consequence.
2. **Declining a win reward.** A winner can currently press Back on the reward-selection screen and leave without taking a card. This may be desirable, but it should be an explicit rule.
3. **NPC stake choice.** On a loss, the NPC currently takes the player card with the highest side-value total. Once rarity/tier design is final, decide whether stake choice remains deterministic, uses card points/rarity, or becomes opponent-specific.
4. **Multiple RPG save slots.** Triple Triad saves currently use global `user://triple_triad_*.cfg` paths because the project has no broader save-slot service. If the RPG later supports multiple campaign slots, these files should be namespaced by the active slot rather than copied into a parallel save system now.
5. **Same Wall / Elemental.** Their fields are reserved but runtime validation now rejects them. Implement only if they belong in your final ruleset.

## UI integration contract

The redesigned UI should prefer the public API/signal surface rather than reading backend files directly:

- `get_player_snapshot()`
- `get_collection_snapshot()`
- `get_deck_profiles_snapshot()`
- `get_opponent_snapshot(opponent_id)`
- `get_opponents_snapshot()`
- `get_global_triple_triad_snapshot()`
- `backend_state_changed(reason)`
- `get_backend_health()`

This keeps the next visual pass replaceable without coupling it to save schemas or card-economy implementation details.
