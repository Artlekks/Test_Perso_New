# Triple Triad Runtime Recovery & Save Hardening V1

This pass hardens the real card-game loop against interruption, reload, and
partial reward delivery. It adds no card rules, balance changes, or UI layout.

## Mandatory match-result journal

Every decisive non-QA match now persists the mandatory reward/loss resolution
before the result screen can transfer ownership.

The journal records:
- opponent and winner;
- the exact five cards shown for both sides;
- eligible reward ids;
- the protected/forced loss card;
- tournament transition state;
- a selected card and its intended ownership quantities once chosen.

If the game is closed before a card is chosen, the reward screen resumes on the
next boot and must be completed before another card match can start.

If interruption happens after the card was chosen, startup reconciles ownership
to the exact intended quantities and repairs the associated acquisition /
stolen-card counters idempotently. The resolved journal is then cleared.

Minimum-deck-protected losses require no ownership transfer and are safely
finalized on reload.

## Card transfer metadata reconciliation

Acquisition history and encounter stolen-card state now expose absolute
reconciliation APIs. Recovery therefore restores the intended counters instead
of replaying additive events and risking duplicate statistics.

The card economy's forced recovery path uses its existing transfer journal too,
so a second interruption during recovery is still recoverable.

## One-shot world reward transaction

Treasure, quest, and tournament one-shot rewards now persist the chosen card
before granting it.

The world reward ledger stores:
- event id;
- source type/id;
- exact chosen card;
- source context;
- owned quantity before delivery.

If interruption occurs:
- before grant: the same chosen card is delivered on next boot;
- after grant but before event completion: the existing quantity proves delivery
  occurred and the event is completed without granting a second card.

This closes the old duplicate-reward window.

The world reward ledger schema is now 2 and loads schema-1 saves normally.

## Tournament completion reward

Competition state now persists a pending championship reward independently from
the active tournament.

A completed tournament cannot start another tournament until this reward has
been resolved or acknowledged. Startup repairs the reward through the same
transactional world-reward path.

Competition save version is now 3.

## Stale tournament deck recovery

On startup, a persisted active tournament with a locked deck is checked against:
- current ownership;
- current Duel Rank/card eligibility;
- the required five unique cards.

If the persisted deck is no longer legal, the attempt is abandoned safely
instead of leaving the player in a broken tournament state.

## Runtime inspection

`TripleTriadGame.reconcile_runtime_state()`
`TripleTriadGame.get_runtime_recovery_snapshot()`

The global Triple Triad snapshot now contains `recovery`.

Save-integrity manifests also report `resolution_pending`, and healthy backups
are not refreshed while a mandatory match reward is unresolved.

## QA

New regression tests cover:
- pending tournament rewards;
- mandatory match-resolution journal round-trip;
- transactional one-shot world reward delivery.

Expected backend QA count: 41.
