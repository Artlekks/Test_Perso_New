# Triple Triad Balance Iteration V2

This pass responds to the first 800-game automated report (seed 1337).

## What the first report exposed

- 800/800 games were valid, so the resolver/AI simulation path is stable.
- First player won only ~30% of decisive games. The simulator now breaks this down by host rules/region and by each ordered matchup instead of hiding it in one global number.
- Tide Oracle underperformed its intended rung despite paying for five Influence cards.
- Ash Champion's old Volcanic +1 edge-center trait disproportionately helped weaker cards because ranks cap at 10, flattening the Champion's stat advantage.

## AI changes

- Deck cost is no longer treated as something to conserve during a duel. It is a deck-building constraint, and conserving expensive cards artificially benefits the second player because their fifth unplayed card still counts toward score.
- Influence AI now values:
  - immediate pressure on enemy cards,
  - zone denial on strategically useful empty cells,
  - capturing enemy Influence sources (because their field flips next action),
  - survival of the Influence source itself.
- All AI profiles now have a vulnerability term that estimates whether an exposed side can be immediately beaten by an opponent reply.
- Controller and Champion profiles received the strongest tactical weights; Aggressive remains capture-first and Defensive remains safety-first.

## Opponent tuning

### Tide Oracle

- Authored deck is now Undertow / Wharf Cat / Cira / Nia / River Drake.
- Cost/budget is 38.
- Still five Influence cards; this is a tactical-control improvement rather than a raw archetype change.
- Content revision bumped to 2.

### Ash Champion

- Champion still uses Same + Plus + Combo + Influence.
- Volcanic Magma Veins changed from +1 to -1 on edge-center cells.
- This avoids the previous rank-cap effect where low cards gained more effective value from the home field than premium cards.
- Content revision bumped to 2.

## Simulator V2 output

The JSON now includes:

- `global.second_player_win_rate`
- `global.turn_order_bias`
- `turn_order_by_host`: first/second-player rates split by the host's rule/region context
- per-matchup starting/second-player win rates
- `ladder_checks`: each adjacent Duel Rank rung compared over both home contexts

Ladder target band is 55%-75% decisive wins for the higher rung. This is diagnostic, not a runtime rule.

The report also computes two **diagnostic-only** initiative candidates without changing live match rules: what the result distribution would have been if the starting player received +1 or +2 final score. This lets us measure a possible turn-order compensation before committing it to gameplay.
