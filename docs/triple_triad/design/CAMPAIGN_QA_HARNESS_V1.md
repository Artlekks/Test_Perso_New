# Triple Triad Campaign QA Harness V1

## Keys

- Normal F10 in fishing/exploration: existing Fishing QA.
- F10 while Triple Triad is open: existing Match QA.
- Shift+F10 anywhere: Triple Triad Campaign QA.

Campaign QA uses:
- W/S: select
- A/D: switch Scenarios / Actions
- K / Enter: apply
- Shift+F10, I, Escape: close

## Scenario profiles

Fresh / Undiscovered
- zero cards
- Duel Rank 1
- Triple Triad locked
- next eligible Ocean 2 catch naturally discovers the Saltworn Card Case

Starter / Just Unlocked
- the real five-card Saltworn Card Case starter deck
- Duel Rank 1
- card game unlocked
- deck profiles reset; Deck #1 rebuilds from owned cards

Hour 1 / Learn Loop
- Rank 1
- 8 owned cards selected only from the canonical 13-card first-hour pool
- Beach Trader has one recorded first win
- useful for testing the first collection-growth loop without impossible cards

Five-Card Safety
- exactly the five canonical starter cards
- intended test: deliberately lose
- the production stake policy must refuse the ownership transfer rather than leave the player with four cards

Six-Card Loss / Recovery
- the five canonical starter cards plus one reachable first-hour card
- intended test: lose once to hit the protected five-card floor, then rematch to recover the stolen card

Veteran Rematch Ready
- Rank 2
- 32 cards drawn only from the canonical first-twelve-hour pool
- Beach Trader, Pier Apprentice and Gearwright prerequisites are satisfied
- Dock Bruiser has six recorded wins for immediate Stage-3 rematch testing

Hour 4 / Connected Systems
- Rank 2
- 20 owned cards from the canonical 24-card first-four-hour pool
- Beach Trader -> Pier Apprentice -> Gearwright are cleared
- Card Maker outputs are part of the reachable pool instead of arbitrary rank-legal cards

Hour 12 / Specialization
- Rank 2
- 35 owned cards from the canonical 40-card first-twelve-hour pool
- Beach Trader, Pier Apprentice, Gearwright, Dock Bruiser and Marsh Keeper are cleared
- deeper-coast salvage is reachable through the same authored progression structure

Mid Game
- Rank 3
- 60 deterministic legal cards
- early progression partly complete

Regional Championship Ready
- Rank 3
- all three regional circuits complete
- Regional Championship immediately testable

Regional Round 2 Resume
- Rank 3
- an active Regional Championship run already at round 2
- locked deck uses the canonical five-card starter deck

Masters' Cup Ready
- Rank 5
- one Regional Championship clear
- Masters' Cup immediately testable

Collection 170 / 179
- Rank 6
- Card Master campaign state
- exactly nine cards missing

Full Completion
- Rank 6
- 179 / 179 cards
- all authored opponents beaten
- Regional Championship and Masters' Cup cleared

## Canonical early acquisition spine

The QA harness reads `early_progression_plan_v1.json` and `world_acquisition_map.json` instead of inventing early collections from card rank alone.

Expected cumulative primary pools:
- starter: 5
- hour 1 / learn loop: 13
- hour 4 / connected systems: 24
- hour 12 / specialization: 40

The backend QA suite validates that Campaign QA still resolves those exact four pool sizes and that the six-card recovery preset can genuinely create six reachable cards.

## Actions

Next Ocean 2 Catch = Coast Salvage Card
- preserves the current campaign
- sets the existing coast-salvage counter to 3/4
- the next eligible Ocean 2 catch uses the real mapped salvage reward path

Reset Deck Profiles Only
- deletes only Triple Triad deck profiles/backups
- does not touch collection, Duel Rank, fishing, encounters, or tournaments
- scene reloads and Deck #1 is rebuilt from currently owned legal cards

Reconcile Runtime / Save State
- runs the production recovery/reconciliation path

Run Backend QA
- runs the existing regression suite in place

## Five-card floor

The normal economy policy already protects the last playable five-card collection. This is deterministic and is not tied to fishing RNG.

Fishing is an acquisition/variety path, not a rescue mechanic required to keep the card game playable.

## Reset boundary

Scenario resets delete only `user://triple_triad_*` state and its backups. Fishing progression/save state is deliberately untouched.
