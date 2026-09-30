TRIPLE TRIAD OPPONENT / ENCOUNTER REGISTRY PASS

Purpose
=======
Adding a card-playing NPC should now be data authoring, not new gameplay code.

Authoritative registry
======================
res://data/triple_triad/opponents/opponent_registry.tres

Each entry is a TripleTriadOpponentProfile and contains:
- stable opponent_id
- display name
- opponent Duel Rank
- minimum player Duel Rank
- enabled flag
- encounter tags
- AI personality
- region
- optional rule-set override
- card level range
- optional deck-point budget override
- authored native collection
- preferred five-card deck
- initial collection size
- progression reward on victory

Runtime lookup
==============
TripleTriadGame now exposes:
    open_game_by_id(&"beach_trader")

TripleTriadOpponentNPC uses opponent_id first and keeps its old direct
opponent_profile reference only as a compatibility fallback.

Registry queries
================
The registry supports:
- get_opponent(id)
- has_opponent(id)
- get_all_opponents()
- get_available_opponents(player_rank, region_id, required_tag)
- validate_registry(card_catalog)

This gives future towns/regions/story systems a clean way to ask which card
players are currently available without reaching into match code.

Current content
===============
Beach Trader is the first registered opponent.
Its current prototype behavior has deliberately not been rebalanced.
native_card_ids remains empty for now, so the existing deterministic collection
seeding remains active until the deliberate card-authoring pass.
