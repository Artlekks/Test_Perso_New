# Triple Triad Balance Iteration V7

V6 established the correct six-rank progression spine but exposed two remaining
calibration problems.

## 1. Fresh-save deck quality

Deck #1 previously sorted owned cards by lowest cost and then lowest rank total.
That meant the automatic fresh-save deck used the weakest five cards in the
starter collection (21 points / 54 printed rank) even though the same collection
contains a legal 27-point / 70-rank deck.

V7 changes only automatic new-profile construction. Existing saved player decks
are never overwritten. The default builder now searches a small deterministic
candidate set and maximizes printed rank total while preserving the budget.

The balance report now includes `starter_benchmark`, using this same best starter
logic against Beach Trader under neutral Basic rules.

## 2. Compress the authored ladder

V6 neutral results were:
- Beach -> Dock: 98.7% for Dock
- Dock -> Highland: 75.4% for Highland
- Highland -> Tide: 76.1% for Tide
- Tide -> Storm: 98.4% for Storm
- Storm -> Ash: 65.6% for Ash

The two ~75% results are close enough to the intended 55-75 target that V7 avoids
large changes there.

V7 authored printed-rank totals:
- Beach Trader: 72 (unchanged)
- Dock Bruiser: 82 (from 88)
- Highland Keeper: 83, with a less spike-heavy geometry
- Tide Oracle: 85 (unchanged)
- Storm Captain: 94 (from 110)
- Ash Champion: 104 (from 121)

Storm and Ash are compressed together so the healthy final-rung relationship is
not destroyed while reducing the Rank 4 -> Rank 5 cliff.

Primary V7 checks:
1. `starter_benchmark` should put Beach around 50-72% decisive wins.
2. Neutral adjacent rungs should generally land around 55-75%.
3. Do not change live initiative scoring; V6 had no invalid games and the +1
   candidate would already favor the starting player.
