# Triple Triad Balance Iteration V3

Based on the second 800-game deterministic suite.

## What V2 proved
- Global first-player decisive win rate improved from ~30% to ~42.5%.
- A hypothetical +1 final-score initiative point lands almost exactly at 50/50 globally, but local host/rule bias is still large, so the live scoring rule is intentionally unchanged for now.
- Dock Bruiser completely dominates Beach Trader.
- Highland Keeper vs Dock Bruiser is already in the target band.
- Tide Oracle was over-corrected and dominates Highland too strongly.
- Ash Champion is strong overall but its all-special-rules home game creates too much volatility, including beginner upsets.

## V3 changes
1. Beach Trader receives a modestly stronger 25-point deck while keeping one Influence teaching card.
2. Dock Bruiser moves to a dedicated Dock region: two opposite +1 anchor corners. This is intended to reduce the extreme second-player bias seen under Coast + Basic rules.
3. Tide Oracle returns Nia -> Gimbal and drops from 38 to 37 points. Controller AI keeps the tactical V2 rewrite but uses less extreme Plus/Influence weights.
4. Ash Champion keeps Same + Combo + Influence but no longer enables Plus at home. Tide remains the dedicated Plus/Influence specialist.
5. The simulator now reports the +1 initiative candidate per host/ruleset, not just globally.

## Deliberately unchanged
- Core 10-card scoring / draw rule.
- Highland Keeper, whose adjacent-rung result is already on target.
- Ash Champion deck and AI.
- Stable card IDs and 179-card roster.

Run the same 800-game suite with seed 1337 for a clean V2 -> V3 comparison.
