# Triple Triad World Delivery Runtime V1

This pass turns the authored 179-card acquisition map into runtime gameplay
delivery paths without adding card-game UI.

## Fishing salvage

After the Saltworn Card Case has unlocked Triple Triad, committed catches at
`ocean_2` increment a persistent salvage counter.

Every fourth eligible catch attempts to grant one unowned card from:

- `fishing_salvage:coast_shallows`

The source always prefers cards the player does not own. Once all cards in that
source are owned, the backend returns `source_complete` instead of generating
duplicates.

The counter lives in `user://triple_triad_world_delivery.cfg`, so reloading the
scene does not reset progress toward the next salvage card.

Future marsh/deep fishing zones can map to the existing `marsh_reeds` and
`deep_water` sources without changing the card acquisition backend.

## Treasure/cache delivery

`TripleTriadWorldRewardTrigger.tscn` is a reusable Area2D interaction component.
It defaults to:

- source type: `treasure_cache`
- source id: `harbor_lockbox`
- interaction key: K
- one-shot: true

Give each placed cache a stable `event_id`. Successful one-shot claims are saved
in the world reward ledger, so reloading the scene cannot farm the same cache.

## Quest hook

Quest code can award a mapped card with:

`TripleTriadGame.claim_quest_card_reward(source_id, quest_event_id, source_context)`

Quest event IDs are one-shot and persisted by the same ledger.

## Tournament hook

Tournament code can award a mapped card with:

`TripleTriadGame.claim_tournament_card_reward(source_id, tournament_event_id, source_context, one_shot)`

This supports both one-time championship prizes and repeatable tournament reward
logic.

## Generic runtime API

All direct world systems ultimately call:

`claim_world_source_reward(source_type, source_id, source_context, event_id, one_shot)`

The backend validates the source against the acquisition map, enforces Duel Rank,
selects only unowned cards, grants ownership through the existing acquisition
service, records history, invalidates State API caches, and checkpoints the
Triple Triad save.

## Result-screen regression

This patch also carries the reward-view parser hotfix:

`_focus_card.global_position = source_view.global_position`

The invalid `Control.to_local()` call is not present.

## QA

A new backend QA test validates the four direct world-delivery source families
and their required baseline source IDs.

Expected QA count after this pass: 28.
