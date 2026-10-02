# Triple Triad Competitive Progression V1

## Regional circuits

Circuits are derived from the real persistent opponent encounter records.

Harbor Circuit:
- Pier Apprentice
- Beach Trader
- Dock Bruiser
- Gearwright

Highland Circuit:
- Marsh Keeper
- Highland Keeper

Mystic Circuit:
- Lantern Gambler
- Tide Oracle

All three circuits plus Duel Rank 3 unlock the Regional Card Championship.

## Regional Card Championship

Three real rounds:
1. Gearwright
2. Marsh Keeper
3. Tide Oracle

A loss ends the attempt. Draws use the normal match replay behavior and do not
consume a tournament round.

Every complete clear awards one unowned card from the existing
`tournament_reward/regional_circuit` pool. The first clear awards the
`Regional Champion` title. The tournament stays repeatable so its full card pool
can be collected.

## Masters' Cup

Requirements:
- Duel Rank 5
- at least one Regional Card Championship clear

Four real rounds:
1. Lantern Gambler
2. Wandering Sage
3. Storm Captain
4. Ash Champion

The ordering intentionally satisfies Ash Champion's existing Storm Captain
prerequisite during the tournament itself.

Every clear awards one unowned card from the existing
`tournament_reward/masters_cup` pool. The first clear awards `Card Master` and
sets `card_game_completed = true`.

The Masters' Cup remains repeatable after campaign completion so the full
Masters' Cup reward pool can be collected.

## Runtime API

- `get_competitive_snapshot()`
- `get_circuit_snapshot(circuit_id)`
- `get_competition_snapshot(competition_id)`
- `start_competition(competition_id)`
- `start_competition_and_open(competition_id)`
- `open_active_competition_match()`
- `abandon_active_competition()`

Tournament progress is saved to `user://triple_triad_competitions.cfg` and is
included in the save-integrity backup set.

The tournament layer never simulates substitute matches. Every round uses the
normal NPC profile, rules, deck, stakes, stolen-card recovery, progression and
reward pipeline.

Expected backend QA count: 31.
