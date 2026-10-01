Triple Triad opponent registry
==============================

V1 authored ladder:
- beach_trader      : beginner balanced, Rank 1
- dock_bruiser      : aggressive, Rank 2
- highland_keeper   : defensive, Rank 3
- tide_oracle       : Influence/control, Rank 4
- ash_champion      : champion, Rank 6

Each profile owns:
- a deterministic native collection,
- an authored five-card preferred deck,
- an AI profile,
- a region/rule configuration,
- a player-rank availability gate,
- progression points on win,
- a normal reward pool,
- a content_revision for development-safe NPC collection migration.

Cards previously stolen from the player remain priority deck cards and are also
made selectable as rewards on a successful rematch, even when they are not in
the opponent's normal reward pool.
