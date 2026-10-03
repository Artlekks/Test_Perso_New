extends Node
class_name FishingPreparedBaitService

signal auto_use_changed(enabled: bool)
signal cast_bait_changed(snapshot: Dictionary)
signal prepared_bait_consumed(result: Dictionary)

var economy_config: FishingEconomyConfig = null
var item_catalog: GameItemCatalogService = null
var player_inventory: PlayerItemInventory = null
var transaction_service: GameItemTransactionService = null

var _auto_use_enabled: bool = true
var _cast_active: bool = false
var _last_use_result: Dictionary = {}


func configure(
	new_economy_config: FishingEconomyConfig,
	new_item_catalog: GameItemCatalogService,
	new_player_inventory: PlayerItemInventory,
	new_transaction_service: GameItemTransactionService
) -> void:
	economy_config = new_economy_config
	item_catalog = new_item_catalog
	player_inventory = new_player_inventory
	transaction_service = new_transaction_service
	_auto_use_enabled = (
		economy_config.prepared_bait_auto_use_default
		if economy_config != null
		else true
	)
	_cast_active = false
	_last_use_result.clear()


func set_auto_use_enabled(enabled: bool) -> void:
	if _auto_use_enabled == enabled:
		return
	_auto_use_enabled = enabled
	auto_use_changed.emit(_auto_use_enabled)
	cast_bait_changed.emit(get_runtime_snapshot())


func is_auto_use_enabled() -> bool:
	return _auto_use_enabled


func is_cast_baited() -> bool:
	return _cast_active


func get_owned_count() -> int:
	if player_inventory == null:
		return 0
	var item_id := get_prepared_bait_item_id()
	if item_id == &"":
		return 0
	return player_inventory.get_count(item_id)


func get_prepared_bait_item_id() -> StringName:
	if economy_config == null or item_catalog == null:
		return &""
	return item_catalog.make_item_id(
		GameItemCatalogService.STORAGE_PLAYER,
		economy_config.prepared_bait_item_domain_id
	)


## Commits one prepared-bait portion to a successfully-created cast.
## A cast is never blocked if bait is disabled, unavailable, or cannot save;
## it simply proceeds as a normal lure cast.
func try_begin_cast(persist: bool = true) -> Dictionary:
	if _cast_active:
		clear_cast(&"superseded_cast")

	var result := {
		"used": false,
		"reason": "",
		"item_id": "",
		"remaining_count": get_owned_count(),
		"bite_attraction_multiplier": 1.0,
		"quality_bonus_roll_chance": 0.0,
		"quality_bonus_rolls": 0,
	}
	if not _auto_use_enabled:
		result["reason"] = "auto_use_disabled"
		_last_use_result = result.duplicate(true)
		return result
	if economy_config == null or item_catalog == null or player_inventory == null or transaction_service == null:
		result["reason"] = "prepared_bait_backend_unavailable"
		_last_use_result = result.duplicate(true)
		return result

	var item_id := get_prepared_bait_item_id()
	result["item_id"] = String(item_id)
	if item_id == &"" or item_catalog.get_definition(item_id) == null:
		result["reason"] = "prepared_bait_item_unavailable"
		_last_use_result = result.duplicate(true)
		return result
	if player_inventory.get_count(item_id) <= 0:
		result["reason"] = "no_prepared_bait"
		_last_use_result = result.duplicate(true)
		return result

	var consume: Dictionary = transaction_service.consume_player_items(
		{String(item_id): 1},
		persist,
		&"prepared_bait_cast"
	)
	if not bool(consume.get("success", false)):
		result["reason"] = str(consume.get("reason", "consume_failed"))
		result["transaction"] = consume.duplicate(true)
		result["remaining_count"] = player_inventory.get_count(item_id)
		_last_use_result = result.duplicate(true)
		return result

	_cast_active = true
	result["used"] = true
	result["reason"] = "completed"
	result["remaining_count"] = player_inventory.get_count(item_id)
	result["bite_attraction_multiplier"] = get_bite_attraction_multiplier()
	var generation := get_specimen_generation_context()
	result["quality_bonus_roll_chance"] = float(
		generation.get("prepared_bait_quality_bonus_chance", 0.0)
	)
	result["quality_bonus_rolls"] = int(
		generation.get("prepared_bait_quality_bonus_rolls", 0)
	)
	result["transaction"] = consume.duplicate(true)
	_last_use_result = result.duplicate(true)
	prepared_bait_consumed.emit(result.duplicate(true))
	cast_bait_changed.emit(get_runtime_snapshot())
	return result


func clear_cast(reason: StringName = &"cast_finished") -> void:
	if not _cast_active:
		return
	_cast_active = false
	var snapshot := get_runtime_snapshot()
	snapshot["clear_reason"] = String(reason)
	cast_bait_changed.emit(snapshot)


func get_bite_attraction_multiplier() -> float:
	if not _cast_active or economy_config == null:
		return 1.0
	return clampf(
		economy_config.prepared_bait_bite_attraction_multiplier,
		1.0,
		2.0
	)


func get_specimen_generation_context() -> Dictionary:
	if not _cast_active or economy_config == null:
		return {
			"prepared_bait_quality_active": false,
			"prepared_bait_quality_bonus_chance": 0.0,
			"prepared_bait_quality_bonus_rolls": 0,
		}
	var chance := clampf(
		economy_config.prepared_bait_quality_bonus_roll_chance,
		0.0,
		0.75
	)
	var rolls := clampi(
		economy_config.prepared_bait_quality_bonus_rolls,
		0,
		2
	)
	return {
		"prepared_bait_quality_active": chance > 0.0 and rolls > 0,
		"prepared_bait_quality_bonus_chance": chance,
		"prepared_bait_quality_bonus_rolls": rolls,
	}


func get_runtime_snapshot() -> Dictionary:
	var generation := get_specimen_generation_context()
	return {
		"auto_use_enabled": _auto_use_enabled,
		"cast_active": _cast_active,
		"owned_count": get_owned_count(),
		"item_id": String(get_prepared_bait_item_id()),
		"bite_attraction_multiplier": get_bite_attraction_multiplier(),
		"quality_bonus_roll_chance": float(
			generation.get("prepared_bait_quality_bonus_chance", 0.0)
		),
		"quality_bonus_rolls": int(
			generation.get("prepared_bait_quality_bonus_rolls", 0)
		),
		"last_use_result": _last_use_result.duplicate(true),
	}
