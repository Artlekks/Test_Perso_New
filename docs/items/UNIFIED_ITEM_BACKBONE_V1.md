# Unified Item / Inventory / Transaction Backbone V1

This pass introduces the shared RPG item foundation without rewriting the stable fishing/card systems.

## Canonical item identity

All ordinary RPG inventory domains now have one collision-safe item id namespace:

- `player/driftwood`, `player/shell`, ... — generic player items/materials
- `fish/<species_id>` — fish specimens/counts remain owned by FishingInventory
- `lure/<lure_id>` — tackle ownership remains owned by FishingInventory
- `rod/<rod_id>` — tackle ownership remains owned by FishingInventory

The runtime `GameItemCatalogService` bridges the existing beach crafting, fish and tackle catalogs. Crafted lure instances register dynamically when reconstructed or created.

## Generic player inventory

`PlayerItemInventory` is the new persistent stackable-item store at:

`user://player_item_inventory.json`

Beach materials are the first production data migrated into it. The existing `BeachGatheringInventory` class is retained as a compatibility façade, so gather nodes, crafting UI and existing QA do not need to know the storage changed.

Existing `user://beach_gathering_inventory.json` material counts migrate once into the new store. The legacy save is left untouched as a fallback; migration metadata in the new save prevents duplication.

## Unified facade

`GameInventoryFacade` gives UI/gameplay one read API for counts across:

- generic player items/materials
- fish
- lures
- rods

Specialized ownership remains specialized where it matters. Fish keep specimen data instead of being flattened into generic integer items.

## Transactions

`GameItemTransactionService` owns atomic generic stackable costs/rewards. Beach crafting material consumption now reaches this service through the compatibility façade. Failed multi-item costs consume nothing.

Fishing shop purchases and fish sales keep their proven FishingEconomyService transaction path in V1; FishingEconomyAccess now resolves their unified item metadata/category/count through the shared catalog/facade. This is deliberate incremental migration rather than a risky rewrite.

## QA

Debug startup adds a separate item-backend regression suite. Expected:

`Item Backend QA: 6/6 tests passed.`

The existing Beach Crafting QA remains expected at 14/14.
