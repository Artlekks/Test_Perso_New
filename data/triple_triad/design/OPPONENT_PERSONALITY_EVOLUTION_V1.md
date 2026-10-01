# Triple Triad Opponent Personality & Evolution V1

## Philosophy

First-match balance remains frozen. The existing balance simulator still reads
the authored opponent profiles and base AI resources exactly as before.

Rematch evolution is derived from real persistent encounter history:
- Stage 0: baseline, before the player has beaten the NPC.
- Stage 1: after 1 player win.
- Stage 2: after 3 player wins.
- Stage 3: after 6 player wins.

No separate evolution save is required; encounter records are already durable.

## Deck evolution

Each opponent authors three reserve cards. At each new rematch stage one more
reserve card is promoted into the match deck.

Cards stolen from the player remain the first hard deck constraint so recovery
can never be hidden by evolution. Evolved cards fill only the remaining forced
slots.

Small authored budget bonuses allow the new deck to grow without turning early
NPCs into late-game stat walls.

## Signature cards

Each opponent has a signature card that becomes deliberate from Stage 1 onward.
The evolved AI:
- receives a modest penalty for spending the signature card while most board
  cells are still empty;
- receives a modest bonus for using it later.

This is not an absolute rule: a tactically decisive early capture can still
justify playing the signature card.

## Personality learning

Evolution does not apply one generic difficulty multiplier.

- aggressive: stronger capture pressure and card-strength preference;
- defensive / construct / beast: better vulnerability avoidance and edges;
- Influence control: stronger pressure, setup, and source-capture valuation;
- Plus trickster: stronger Plus/setup behavior;
- Same/Combo specialists: stronger Same and future setup planning;
- champion: modest all-round tactical tightening;
- beginner/balanced: positioning and safety improve without huge power growth.

All evolved AI profiles are runtime duplicates. Shared authored `.tres` resources
are never mutated.

## Runtime inspection

`get_opponent_evolution_snapshot(opponent_id)`
`get_active_opponent_evolution_snapshot()`

The debug configuration summary also contains the active rematch stage.

Expected backend QA count: 36.
