# Triple Triad Card Content + Balance v1

This pass turns the compact 179-card portrait roster into an authored gameplay set while preserving every stable `card_id`, compact `atlas_slot`, portrait, and existing Bronze/Silver/Gold frame assignment.

## Rarity identity

- Bronze: 53 cards. Printed rank total is intentionally low/moderate (10-14 in this pass), generally 4-5 Card Points.
- Silver: 99 cards. Printed rank total is 14-20, generally 5-7 Card Points.
- Gold: 27 cards. Printed rank total is 18-27, generally 6-10 Card Points.

Rarity now correlates with strength, but Card Points remain the actual deck-building economy. Influence adds a point premium, so a low-stat control card can still be expensive enough to avoid becoming an automatic include.

## Duel Rank gates

The current six-rank progression is respected. Bronze is broadly usable at Rank 1. Silver gradually reaches Ranks 2-3 as cost rises. Gold begins at Rank 2 and the strongest 10-point Gold cards require Rank 6. This avoids authoring cards that the existing six-rank progression can never unlock.

## Starter collection

Exactly five cards carry the `starter` acquisition tag, matching the canonical Saltworn Card Case: Cindermane, Rustmane, Cliff Ape, Mud Ox, and Dune Horse. Their combined 23 Card Points fit safely below the base 30-point deck budget. Two starter cards demonstrate Pressure from the beginning without making every early card an Influence card. The remaining nearby Bronze creatures are earned through the early acquisition spine instead of being mislabeled as starters.

## Influence distribution

32 / 179 cards project Pressure:

- Bronze: 8
- Silver: 16
- Gold: 8
- Strength 1: 27
- Strength 2: 5

Strength-2 Pressure uses a narrow one-cell pattern. Strength-1 cards use readable 2-3 cell shapes. Rotate continues to rotate both numbers and the authored Influence pattern.

## Identity content

All 179 cards now have unique authored display names. These are original working identities based loosely on the portrait silhouettes; they are not intended to identify the source-game characters. Cards also carry a short flavor line and broad content group (`legend`, `traveler`, `beast`, `construct`, `soldier`, or `townsfolk`) for future NPC pool and collection-filter authoring.

`CARD_ROSTER_V1.csv` is the human-readable full roster: name, stable ID, rarity, ranks, Card Points, Duel Rank requirement, Influence, and starter status.

## Balance philosophy for the next playtest

The first test target is not perfect numerical equality. It is whether deck construction presents real tradeoffs under a 30-point base budget: a stronger Gold card should consume enough budget to force cheaper support, while low-stat Influence cards should remain attractive because of board control. Same + Combo remain baseline and Plus stays optional, so equality-manufacturing Pressure is intentionally scarce rather than universal.
