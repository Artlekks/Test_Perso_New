# Triple Triad World Acquisition Map V1

This pass makes acquisition provenance a validated backend contract rather than a design note.

## Source families

- `starter_bundle` — the Saltworn Card Case; fixed one-shot onboarding cards.
- `opponent_win` — authored `reward_card_ids`; those cards remain tied to specific card players.
- `fishing_salvage` — repeatable source pools resolved by fishing/salvage gameplay.
- `treasure_cache` — cache/chest source pools; event persistence belongs to exploration.
- `quest_reward` — quest/commission source pools; quest state owns one-shot behavior.
- `tournament_reward` — regional/master competition pools.

The acquisition map validates the starter bundle and every opponent reward pool against their real resources, so documentation cannot silently drift away from gameplay.

## Direct claim API

External world systems use:

`TripleTriadGame.claim_world_source_card(source_type, source_id, card_id, source_context)`

Only fishing salvage, treasure caches, quests, and tournament sources can use that direct path. Starter and opponent rewards remain owned by their existing dedicated systems.

## Progression intent

- Common Bronze and early Silver cards come from local salvage, caches, and early jobs.
- Mid Silver cards spread into marsh/deep-water salvage and regional quests.
- Gold Rank 2-4 cards live in the Regional Card Circuit unless already tied to a named opponent.
- Gold Rank 5-6 cards live in the Masters' Cup unless already tied to a named opponent.

## Audit guarantees

Backend startup and QA fail if:

- any source references an unknown card;
- a starter source diverges from the real bundle;
- an opponent source diverges from that opponent's `reward_card_ids`;
- any catalog card has no acquisition source.

V1 covers all 179 cards.
