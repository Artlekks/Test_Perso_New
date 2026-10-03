# Quest Reward World Vertical Slice V1

## Goal

Make the existing `quest_reward` acquisition route player-facing without creating a second quest backend inside Triple Triad.

## Beach request

The beach now contains a reusable **Harbor Request Board**. Once the Saltworn Card Case has unlocked card duels, the request asks the player to defeat the authored **Beach Trader** at least once.

After that persistent encounter condition is satisfied, interacting with the board grants one currently unowned card from the canonical `quest_reward / harbor_errands` pool.

The stable one-shot event ID is:

`beach_demo_harbor_errand_01`

The reward is delivered through `TripleTriadQuestRewardAdapter`, which then delegates to the existing world gateway and world-reward delivery journal.

## Ownership boundaries

- Encounter records own whether Beach Trader has been defeated.
- The request board only reads that persistent condition and exposes the world interaction.
- `TripleTriadQuestRewardAdapter` translates quest completion into a card-reward request.
- The world gateway validates source/rank/discovery rules and performs the actual acquisition.
- The world reward ledger owns crash-safe one-shot delivery.

No generic quest framework was added. A future real quest system can call the same adapter/API and replace the prototype board without changing card acquisition data or saves.

## Player states

- Before card discovery: `Cards : Locked`
- Card game unlocked, Beach Trader not yet beaten: `Request : Beat Beach Trader`
- Beach Trader beaten: `K : Turn In Request`
- Reward claimed: `Request : Complete`
- Entire Harbor Errands source already collected: `Cards : Complete`

## QA

Backend QA checks that the reusable board exists, uses the quest adapter, targets the canonical `harbor_errands` source, has a stable event ID, requires `beach_trader`, and is actually placed in the beach vertical slice.
