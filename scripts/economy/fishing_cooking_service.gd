extends Node
class_name FishingCookingService

signal prepared_bait_cooked(result: Dictionary)

var economy_config: FishingEconomyConfig = null
var item_catalog: GameItemCatalogService = null
var player_inventory: PlayerItemInventory = null
var fishing_inventory: FishingInventory = null
var transaction_service: GameItemTransactionService = null


func configure(
	new_economy_config: FishingEconomyConfig,
	new_item_catalog: GameItemCatalogService,
	new_player_inventory: PlayerItemInventory,
	new_fishing_inventory: FishingInventory,
	new_transaction_service: GameItemTransactionService
) -> void:
	economy_config = new_economy_config
	item_catalog = new_item_catalog
	player_inventory = new_player_inventory
	fishing_inventory = new_fishing_inventory
	transaction_service = new_transaction_service


func get_recipe_snapshot() -> Dictionary:
	if economy_config == null or item_catalog == null:
		return {}
	var snapshot: Dictionary = economy_config.get_prepared_bait_recipe_snapshot()
	snapshot["herb_item_id"] = String(_get_herb_item_id())
	snapshot["prepared_bait_item_id"] = String(_get_prepared_bait_item_id())
	return snapshot


func evaluate_prepared_bait(
	fish_species_id: StringName,
	batch_count: int = 1
) -> Dictionary:
	var result := {
		"can_cook": false,
		"reason": "",
		"fish_species_id": String(fish_species_id),
		"batch_count": maxi(0, batch_count),
		"fish_required": 0,
		"herbs_required": 0,
		"bait_portions_created": 0,
		"fish_owned": 0,
		"herbs_owned": 0,
		"bait_owned": 0,
		"herb_item_id": "",
		"prepared_bait_item_id": "",
	}
	if (
		economy_config == null
		or item_catalog == null
		or player_inventory == null
		or fishing_inventory == null
		or transaction_service == null
	):
		result["reason"] = "cooking_backend_unavailable"
		return result
	if batch_count <= 0:
		result["reason"] = "invalid_batch_count"
		return result
	if not economy_config.is_common_bait_fish(fish_species_id):
		result["reason"] = "fish_not_suitable_for_prepared_bait"
		return result

	var fish_definition: GameItemDefinition = item_catalog.get_by_domain(
		GameItemCatalogService.STORAGE_FISH,
		fish_species_id
	)
	if fish_definition == null:
		result["reason"] = "unknown_fish"
		return result

	var herb_item_id := _get_herb_item_id()
	var bait_item_id := _get_prepared_bait_item_id()
	result["herb_item_id"] = String(herb_item_id)
	result["prepared_bait_item_id"] = String(bait_item_id)
	if (
		herb_item_id == &""
		or item_catalog.get_definition(herb_item_id) == null
	):
		result["reason"] = "herb_item_unavailable"
		return result
	if (
		bait_item_id == &""
		or item_catalog.get_definition(bait_item_id) == null
	):
		result["reason"] = "prepared_bait_item_unavailable"
		return result

	var fish_required: int = (
		maxi(1, economy_config.fish_per_bait_batch) * batch_count
	)
	var herbs_required: int = (
		maxi(1, economy_config.herbs_per_bait_batch) * batch_count
	)
	var bait_created: int = (
		maxi(1, economy_config.portions_per_bait_batch) * batch_count
	)
	var fish_owned: int = fishing_inventory.get_fish_count(
		String(fish_species_id)
	)
	var herbs_owned: int = player_inventory.get_count(herb_item_id)

	result["fish_required"] = fish_required
	result["herbs_required"] = herbs_required
	result["bait_portions_created"] = bait_created
	result["fish_owned"] = fish_owned
	result["herbs_owned"] = herbs_owned
	result["bait_owned"] = player_inventory.get_count(bait_item_id)

	if fish_owned < fish_required:
		result["reason"] = "not_enough_fish"
		return result
	if herbs_owned < herbs_required:
		result["reason"] = "not_enough_herbs"
		return result

	result["can_cook"] = true
	result["reason"] = "ok"
	return result


func cook_prepared_bait(
	fish_species_id: StringName,
	batch_count: int = 1,
	persist: bool = true
) -> Dictionary:
	var result: Dictionary = evaluate_prepared_bait(
		fish_species_id,
		batch_count
	)
	if not bool(result.get("can_cook", false)):
		return result

	var herb_item_id := StringName(str(result.get("herb_item_id", "")))
	var bait_item_id := StringName(
		str(result.get("prepared_bait_item_id", ""))
	)
	var exchange: Dictionary = transaction_service.exchange_fish_and_player_items(
		{
			String(fish_species_id): int(result.get("fish_required", 0)),
		},
		{
			String(herb_item_id): int(result.get("herbs_required", 0)),
		},
		{
			String(bait_item_id): int(
				result.get("bait_portions_created", 0)
			),
		},
		persist,
		&"prepared_bait_cooking"
	)
	if not bool(exchange.get("success", false)):
		result["can_cook"] = false
		result["reason"] = str(exchange.get("reason", "transaction_failed"))
		result["transaction"] = exchange.duplicate(true)
		return result

	result["success"] = true
	result["reason"] = "completed"
	result["fish_owned_after"] = fishing_inventory.get_fish_count(
		String(fish_species_id)
	)
	result["herbs_owned_after"] = player_inventory.get_count(herb_item_id)
	result["bait_owned_after"] = player_inventory.get_count(bait_item_id)
	result["transaction"] = exchange.duplicate(true)
	prepared_bait_cooked.emit(result.duplicate(true))
	return result


func get_prepared_bait_count() -> int:
	if player_inventory == null:
		return 0
	var item_id := _get_prepared_bait_item_id()
	if item_id == &"":
		return 0
	return player_inventory.get_count(item_id)


func _get_herb_item_id() -> StringName:
	if economy_config == null or item_catalog == null:
		return &""
	return item_catalog.make_item_id(
		GameItemCatalogService.STORAGE_PLAYER,
		economy_config.bait_herb_material_id
	)


func _get_prepared_bait_item_id() -> StringName:
	if economy_config == null or item_catalog == null:
		return &""
	return item_catalog.make_item_id(
		GameItemCatalogService.STORAGE_PLAYER,
		economy_config.prepared_bait_item_domain_id
	)
