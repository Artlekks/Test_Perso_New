# Unified Item / Inventory / Transaction Backbone — Pass 2

This pass moves the first complete gameplay loop onto the shared item backbone:

**Gather -> PlayerItemInventory -> Craft -> Merchant**

## Runtime ownership

- `PlayerItemInventory` is the authoritative storage for beach materials.
- `BeachGatheringInventory` remains only as a compatibility adapter for older
  UI/QA callers. In normal session play, its counts come from
  `PlayerItemInventory`.
- `BeachGatheringNode3D` grants materials through
  `FishingSessionServices.grant_beach_material()`, which uses
  `GameItemTransactionService`.
- `BeachCraftingService` evaluates and consumes canonical material item IDs
  directly through `GameItemTransactionService`.
- Crafted-lure creation snapshots material inventory, fishing inventory, and
  crafted-lure records, then rolls all three back on a runtime persistence
  failure.
- Merchant Sell now includes `MATERIALS`. Material sales consume the canonical
  player item and add Zenny as one cross-store transaction.
- Fish remain specialized specimen data and continue through
  `FishingEconomyService`.

## Shared event stream

`GameInventoryFacade.inventory_event` now emits normalized events for:

- player stack counts
- fish counts
- lure counts
- rod counts
- Zenny / Manillo changes
- completed unified transactions

This is the event surface future inventory, toast, quest, and UI systems should
listen to.

## Material sell values

Pass 2 adds provisional, deliberately low beach-material sell values:

- Driftwood: 1z
- Shell: 2z
- Seaweed Fibre: 2z
- Iron Scrap: 3z
- Sea Glass: 4z

These are plumbing values, not final economy balance. Persistent world-resource
state is the next pass; until then, scene reloads can still replenish the
prototype gathering circuit.

## Runtime QA target

Item Backend QA is expanded from **6** checks to **10**. Existing Beach
Crafting QA should remain **14/14**.
