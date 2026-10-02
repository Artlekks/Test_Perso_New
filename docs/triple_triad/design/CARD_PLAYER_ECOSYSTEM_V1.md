# Triple Triad Card-Player Ecosystem V1

## Entry into the card game

A brand-new save now starts with zero Triple Triad cards. Triple Triad is locked
until an acquisition bundle explicitly unlocks it.

The first authored bundle is `salvaged_card_case`: a saltworn waterproof card
case intended to be discovered through fishing/salvage. It grants the ten
starter-tag cards and unlocks the card game. Triple Triad owns the one-shot
ledger and the card contents; the fishing/exploration layer only needs to call:

`TripleTriadGame.claim_salvaged_card_case()`

or use a `TripleTriadAcquisitionTrigger` configured with the bundle id.

This keeps the story hook modular. Future card bundles can come from treasure,
quests, shops, tournaments, fishing, or other systems without changing card
ownership code.

Existing saves are migration-safe: if a pre-system save already owns cards, the
card game remains unlocked and the starter salvage bundle is marked satisfied so
its cards are not duplicated.

## Progression semantics

Opponent progression rewards are now first-clear rewards by default. Rematches
still count in records and still use the normal card stake/reward economy, but
award zero Duel Points unless an opponent explicitly authors a rematch reward.

This makes authored rank thresholds meaningful and prevents grinding one easy NPC
to Rank 6.

## Population

The six balance-tested progression-spine opponents remain:
1. Beach Trader
2. Dock Bruiser
3. Highland Keeper
4. Tide Oracle
5. Storm Captain
6. Ash Champion

Five side/world card players have been added:
- Pier Apprentice — Rank 1 casual beginner
- Gearwright — Rank 2 construct/defensive
- Marsh Keeper — Rank 3 beast/defensive
- Lantern Gambler — Rank 4 Plus/Influence trickster
- Wandering Sage — Rank 5 Same/Combo traveler

Side opponents provide alternative cards and first-clear Duel Points without
being included in the automated spine balance suite. The simulator now asks the
registry for `get_progression_spine()` so expanding the world population does not
turn every balance run into thousands of irrelevant all-pairs matches.

Ash Champion additionally requires Storm Captain to have been beaten, preserving
the final capstone even if side opponents let the player reach Duel Rank 5 by an
alternate route.

## Availability API

Opponent availability can now depend on:
- card-game unlock state
- player Duel Rank
- region/tag filters
- total card-duel wins
- specific previously defeated opponents

Useful public TripleTriadGame calls:
- `is_card_game_unlocked()`
- `get_acquisition_snapshot()`
- `claim_acquisition_bundle(bundle_id, source_context)`
- `claim_salvaged_card_case()`
- `get_opponent_availability(opponent_id)`
- `get_available_card_player_ids(region_id, required_tag)`

State API schema 5 exposes the same unlock/acquisition state for future menus,
quests, and world logic.
