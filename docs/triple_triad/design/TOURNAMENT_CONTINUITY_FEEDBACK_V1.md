# Triple Triad Tournament Continuity & Runtime Feedback V1

## Tournament continuity

A tournament attempt now behaves as one run rather than several disconnected
normal matches.

- The player chooses a legal five-card deck once, before round one.
- The competition service persists those five stable card ids.
- The same deck is used for every later round in the attempt.
- After the mandatory opponent-card reward resolves, a won round immediately
  loads the next tournament opponent and starts the next match.
- Draws still replay the same round.
- A loss clears the active tournament and the locked deck.
- Cancelling deck selection before round one abandons the attempt.
- While a tournament is active, ordinary card-player challenges are rejected;
  only the tournament's expected next opponent can open.

The locked deck is stored in `user://triple_triad_competitions.cfg`, so an
active tournament can be resumed after leaving/reloading.

## Runtime gameplay event feed

The backend now exposes a bounded FIFO event feed for future HUD/toast/dialogue
presentation without putting UI concerns into the game systems.

API:
- `get_pending_gameplay_events()`
- `pop_next_gameplay_event()`
- `clear_gameplay_events()`

Signal:
- `gameplay_event_queued(event)`

Current event types include:
- `bundle_acquired`
- `card_game_unlocked`
- `card_acquired`
- `opponent_card_won`
- `card_lost`
- `duel_rank_up`
- `tournament_round_won`
- `tournament_next_round`
- `tournament_failed`
- `tournament_cleared`
- `collection_milestone`
- `collection_complete`

The feed is intentionally presentation-neutral. A later HUD can render a toast,
dialogue card, journal entry, or nothing at all without changing the backend.

## Exploration rematch feedback

Card-player NPC prompts now reflect persistent rematch progression:
- first encounter: authored normal prompt;
- Stage 1/2: `K : Rematch`;
- Stage 3: `K : Veteran Rematch`.

Expected backend QA count after this pass: 38.
