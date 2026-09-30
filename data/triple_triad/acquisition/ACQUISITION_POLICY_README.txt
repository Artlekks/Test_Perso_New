TRIPLE TRIAD CARD ACQUISITION / PROGRESSION POLICY PASS

What changed
============
1. New-save starter collection
   New Triple Triad saves no longer need to begin with every card.
   The default policy awards 10 deterministic low-point cards tagged "starter".
   Existing player collections are NEVER reset or replaced by this patch.

2. Card acquisition metadata
   card_stats.json schema is now version 2. Every current portrait card has:
   - rarity: "standard"
   - required_player_rank: 1
   - acquisition_tags: ["starter", "opponent_win"]

   This deliberately does NOT rebalance the current 179 cards yet. Later content
   authoring can change these fields per character/boss/grunt.

3. Duel Rank gating
   Cards can be owned regardless of rank.
   A card may be placed in a deck only when the player's Duel Rank meets its
   required_player_rank.
   All current cards are Rank 1, so nothing currently owned becomes locked.

4. Existing Duel Rank gates now have clear responsibilities
   - Player Duel Rank increases deck point budget.
   - Opponent profiles can require a minimum player Duel Rank.
   - Cards can require a minimum player Duel Rank for deck use.
   - Ownership itself is NOT deleted/blocked by rank.

5. Acquisition history
   user://triple_triad_acquisition_history.cfg records:
   - total acquisitions/losses per card
   - first and latest acquisition source
   - latest opponent involved
   - latest event timestamp
   - global event count

   Current real sources:
   - opponent_win
   - opponent_loss

6. NPC ownership
   The existing persistent per-opponent collection remains authoritative.
   native_card_ids/preferred_deck_ids in opponent profiles are still the authored
   way to define permanent NPC card content.
   No arbitrary native pools were assigned in this pass because character/card
   importance has not been authored yet.

7. Starter policy
   res://data/triple_triad/acquisition/default_acquisition_policy.tres
   Current prototype:
   - 10 starting cards
   - must have the "starter" acquisition tag
   - Rank 1 eligible
   - lowest point cost first, deterministic ties
   - duplicate ownership remains supported
   - rank gating is enforced for deck use

This is backend-focused. Final rarity names, card tiers, rank requirements,
starter cards and NPC native collections can be authored later without changing
the acquisition code.
