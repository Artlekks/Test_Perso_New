# Triple Triad Card Economy Integrity V1

This pass formalizes stake safety and stolen-card recovery without changing
normal match rules.

## Minimum playable collection protection

A player can never lose ownership of a card if that transfer would leave fewer
than five distinct cards currently usable at their Duel Rank.

Default policy:
- minimum playable unique cards: 5
- protection enabled
- duplicate copies can still be staked because one copy remains
- cards locked above the current Duel Rank do not count toward the protected
  five-card playable minimum

If no safe stake exists, the loss still counts as a match loss but ownership does
not transfer. The result screen reports that the last playable deck is protected
and waits for K before returning.

## Normal stakes

When more than the protected minimum is available, the existing deterministic
stake rule remains:
1. highest deck cost
2. highest printed rank total
3. lexicographically lowest stable card ID

## Recovery

Existing recovery behavior remains authoritative:
- a stolen card is transferred into the opponent's persistent collection;
- it is promoted into that opponent's priority/deck set;
- priority cards are always eligible reward choices on a rematch;
- the encounter record tracks outstanding stolen quantities and recovered cards.

`TripleTriadGame.get_card_economy_snapshot()` now exposes:
- total owned cards
- unique owned cards
- playable unique cards at current Duel Rank
- whether minimum-deck protection is active
- outstanding stolen-card totals by opponent

## QA

Adds a regression test proving:
- exactly five playable unique cards cannot be reduced to four;
- a duplicate copy of the strongest card remains a safe stake.

Expected backend QA count: 29.
