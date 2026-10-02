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
- the real ten starter cards
- Duel Rank 1
- card game unlocked
- deck profiles reset; Deck #1 rebuilds from owned cards

Five-Card Safety
- exactly five unique playable starter cards
- intended test: deliberately lose
- the production stake policy must refuse the ownership transfer rather than
  leave the player with four cards

Early Game
- Rank 2
- 24 deterministic legal cards
- a couple of early NPC first wins

Mid Game
- Rank 3
- 60 deterministic legal cards
- early progression partly complete

Regional Championship Ready
- Rank 3
- all three regional circuits complete
- Regional Championship immediately testable

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

The normal economy policy already protects the last playable five-card
collection. This is deterministic and is not tied to fishing RNG.

Fishing is an acquisition/variety path, not a rescue mechanic required to keep
the card game playable.

## Reset boundary

Scenario resets delete only `user://triple_triad_*` state and its backups.
Fishing progression/save state is deliberately untouched.
