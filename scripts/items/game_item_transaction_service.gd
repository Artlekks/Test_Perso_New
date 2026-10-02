extends Node
class_name GameItemTransactionService

signal transaction_completed(result: Dictionary)

var item_catalog: GameItemCatalogService = null
var player_inventory: PlayerItemInventory = null
var inventory_facade: GameInventoryFacade = null
var fishing_inventory: FishingInventory = null


func configure(
	new_catalog: GameItemCatalogService,
	new_player_inventory: PlayerItemInventory,
	new_inventory_facade: GameInventoryFacade,
	new_fishing_inventory: FishingInventory = null
) -> void:
	item_catalog = new_catalog
	player_inventory = new_player_inventory
	inventory_facade = new_inventory_facade
	fishing_inventory = new_fishing_inventory


func evaluate_player_costs(costs: Dictionary) -> Dictionary:
	var result := {
		"can_afford": false,
		"reason": "",
		"missing": {},
		"normalized_costs": {},
	}
	if item_catalog == null or player_inventory == null:
		result["reason"] = "item_backend_unavailable"
		return result

	var normalized: Dictionary = {}
	var missing: Dictionary = {}
	for raw_id in costs.keys():
		var item_id := StringName(str(raw_id))
		var amount: int = maxi(0, int(costs[raw_id]))
		if amount <= 0:
			continue
		var definition: GameItemDefinition = item_catalog.get_definition(
			item_id
		)
		if definition == null:
			result["reason"] = "unknown_item"
			result["unknown_item_id"] = String(item_id)
			return result
		if (
			definition.storage_kind
			!= GameItemCatalogService.STORAGE_PLAYER
		):
			result["reason"] = "non_player_storage_cost"
			result["unsupported_item_id"] = String(item_id)
			return result
		normalized[String(item_id)] = amount
		var owned: int = player_inventory.get_count(item_id)
		if owned < amount:
			missing[String(item_id)] = amount - owned

	result["normalized_costs"] = normalized
	result["missing"] = missing
	if not missing.is_empty():
		result["reason"] = "missing_items"
		return result
	result["can_afford"] = true
	result["reason"] = "ok"
	return result


func consume_player_items(
	costs: Dictionary,
	persist: bool = true,
	context: StringName = &""
) -> Dictionary:
	var evaluation: Dictionary = evaluate_player_costs(costs)
	if not bool(evaluation.get("can_afford", false)):
		return evaluation

	var snapshot: Dictionary = (
		player_inventory.create_transaction_snapshot()
	)
	player_inventory.begin_notification_batch()
	var result: Dictionary = player_inventory.consume_costs(
		evaluation.get("normalized_costs", {}),
		false
	)
	if not bool(result.get("success", false)):
		player_inventory.restore_transaction_snapshot(
			snapshot,
			false
		)
		player_inventory.cancel_notification_batch()
		result["reason"] = "consume_failed"
		return result

	if persist and not player_inventory.commit_changes():
		player_inventory.restore_transaction_snapshot(
			snapshot,
			false
		)
		player_inventory.cancel_notification_batch()
		result["success"] = false
		result["reason"] = "save_failed"
		return result

	result["reason"] = "completed"
	result["context"] = String(context)
	player_inventory.commit_notification_batch()
	_emit_completed(result)
	return result


func grant_player_items(
	rewards: Dictionary,
	persist: bool = true,
	context: StringName = &""
) -> Dictionary:
	var result := {
		"success": false,
		"reason": "",
		"granted": {},
		"context": String(context),
	}
	if item_catalog == null or player_inventory == null:
		result["reason"] = "item_backend_unavailable"
		return result

	var normalized: Dictionary = {}
	for raw_id in rewards.keys():
		var item_id := StringName(str(raw_id))
		var amount: int = maxi(0, int(rewards[raw_id]))
		if amount <= 0:
			continue
		var definition: GameItemDefinition = item_catalog.get_definition(
			item_id
		)
		if definition == null:
			result["reason"] = "unknown_item"
			result["unknown_item_id"] = String(item_id)
			return result
		if (
			definition.storage_kind
			!= GameItemCatalogService.STORAGE_PLAYER
		):
			result["reason"] = "non_player_storage_reward"
			result["unsupported_item_id"] = String(item_id)
			return result
		normalized[String(item_id)] = amount

	var snapshot: Dictionary = (
		player_inventory.create_transaction_snapshot()
	)
	player_inventory.begin_notification_batch()
	for raw_id in normalized.keys():
		var grant_item_id := StringName(str(raw_id))
		var grant_amount: int = int(normalized[raw_id])
		player_inventory.grant(grant_item_id, grant_amount, false)
		result["granted"][String(grant_item_id)] = grant_amount

	if persist and not player_inventory.commit_changes():
		player_inventory.restore_transaction_snapshot(
			snapshot,
			false
		)
		player_inventory.cancel_notification_batch()
		result["reason"] = "save_failed"
		return result

	result["success"] = true
	result["reason"] = "completed"
	player_inventory.commit_notification_batch()
	_emit_completed(result)
	return result


func exchange_player_items(
	costs: Dictionary,
	rewards: Dictionary,
	persist: bool = true,
	context: StringName = &""
) -> Dictionary:
	var evaluation: Dictionary = evaluate_player_costs(costs)
	if not bool(evaluation.get("can_afford", false)):
		return evaluation
	if item_catalog == null or player_inventory == null:
		return {
			"success": false,
			"reason": "item_backend_unavailable",
		}

	var normalized_rewards: Dictionary = {}
	for raw_id in rewards.keys():
		var item_id := StringName(str(raw_id))
		var amount: int = maxi(0, int(rewards[raw_id]))
		if amount <= 0:
			continue
		var definition: GameItemDefinition = item_catalog.get_definition(
			item_id
		)
		if definition == null:
			return {
				"success": false,
				"reason": "unknown_item",
				"unknown_item_id": String(item_id),
			}
		if (
			definition.storage_kind
			!= GameItemCatalogService.STORAGE_PLAYER
		):
			return {
				"success": false,
				"reason": "non_player_storage_reward",
				"unsupported_item_id": String(item_id),
			}
		normalized_rewards[String(item_id)] = amount

	var snapshot: Dictionary = (
		player_inventory.create_transaction_snapshot()
	)
	player_inventory.begin_notification_batch()
	var consume_result: Dictionary = player_inventory.consume_costs(
		evaluation.get("normalized_costs", {}),
		false
	)
	if not bool(consume_result.get("success", false)):
		player_inventory.restore_transaction_snapshot(
			snapshot,
			false
		)
		player_inventory.cancel_notification_batch()
		return {
			"success": false,
			"reason": "consume_failed",
		}

	var granted: Dictionary = {}
	for raw_id in normalized_rewards.keys():
		var reward_item_id := StringName(str(raw_id))
		var reward_amount: int = int(normalized_rewards[raw_id])
		player_inventory.grant(reward_item_id, reward_amount, false)
		granted[String(reward_item_id)] = reward_amount

	if persist and not player_inventory.commit_changes():
		player_inventory.restore_transaction_snapshot(
			snapshot,
			false
		)
		player_inventory.cancel_notification_batch()
		return {
			"success": false,
			"reason": "save_failed",
		}

	var result := {
		"success": true,
		"reason": "completed",
		"consumed": (
			consume_result.get("consumed", {})
			as Dictionary
		).duplicate(true),
		"granted": granted.duplicate(true),
		"context": String(context),
	}
	player_inventory.commit_notification_batch()
	_emit_completed(result)
	return result


func sell_player_item_for_zenny(
	item_id: StringName,
	amount: int,
	unit_value_zenny: int,
	persist: bool = true,
	context: StringName = &"merchant_sell"
) -> Dictionary:
	var result := {
		"success": false,
		"reason": "",
		"item_id": String(item_id),
		"amount": maxi(0, amount),
		"unit_value_zenny": maxi(0, unit_value_zenny),
		"total_value_zenny": 0,
		"remaining_count": 0,
		"zenny_before": 0,
		"zenny_after": 0,
		"context": String(context),
	}
	if (
		item_catalog == null
		or player_inventory == null
		or fishing_inventory == null
	):
		result["reason"] = "item_backend_unavailable"
		return result
	if amount <= 0:
		result["reason"] = "invalid_amount"
		return result
	if unit_value_zenny <= 0:
		result["reason"] = "not_sellable"
		return result

	var definition: GameItemDefinition = item_catalog.get_definition(
		item_id
	)
	if definition == null:
		result["reason"] = "unknown_item"
		return result
	if (
		definition.storage_kind
		!= GameItemCatalogService.STORAGE_PLAYER
	):
		result["reason"] = "unsupported_storage_kind"
		return result
	if player_inventory.get_count(item_id) < amount:
		result["reason"] = "not_enough_items"
		return result

	var player_snapshot: Dictionary = (
		player_inventory.create_transaction_snapshot()
	)
	var fishing_snapshot: Dictionary = (
		fishing_inventory.create_transaction_snapshot()
	)
	result["zenny_before"] = fishing_inventory.get_zenny()
	_begin_cross_inventory_notifications()

	var consumed: Dictionary = player_inventory.consume_costs(
		{String(item_id): amount},
		false
	)
	if not bool(consumed.get("success", false)):
		player_inventory.restore_transaction_snapshot(
			player_snapshot,
			false
		)
		_cancel_cross_inventory_notifications()
		result["reason"] = "inventory_changed"
		return result

	var total: int = unit_value_zenny * amount
	fishing_inventory.add_zenny(total, false)
	result["total_value_zenny"] = total

	if persist:
		if not player_inventory.commit_changes():
			_rollback_cross_inventory_sale(
				player_snapshot,
				fishing_snapshot
			)
			result["reason"] = "item_save_failed"
			return result
		if not fishing_inventory.commit_changes():
			_rollback_cross_inventory_sale(
				player_snapshot,
				fishing_snapshot
			)
			result["reason"] = "wallet_save_failed"
			return result

	result["success"] = true
	result["reason"] = "completed"
	result["remaining_count"] = player_inventory.get_count(item_id)
	result["zenny_after"] = fishing_inventory.get_zenny()
	result["consumed"] = consumed.get("consumed", {}).duplicate(true)
	_commit_cross_inventory_notifications()
	_emit_completed(result)
	return result


func _begin_cross_inventory_notifications() -> void:
	player_inventory.begin_notification_batch()
	fishing_inventory.begin_notification_batch()


func _commit_cross_inventory_notifications() -> void:
	player_inventory.commit_notification_batch()
	fishing_inventory.commit_notification_batch()


func _cancel_cross_inventory_notifications() -> void:
	player_inventory.cancel_notification_batch()
	fishing_inventory.cancel_notification_batch()


func _rollback_cross_inventory_sale(
	player_snapshot: Dictionary,
	fishing_snapshot: Dictionary
) -> void:
	player_inventory.restore_transaction_snapshot(
		player_snapshot,
		false
	)
	fishing_inventory.restore_transaction_snapshot(
		fishing_snapshot
	)
	# A prior commit in the same cross-store operation may already have reached
	# disk, so rewrite both restored snapshots rather than relying on dirty flags.
	player_inventory.save_to_disk()
	fishing_inventory.save_to_disk()
	_cancel_cross_inventory_notifications()


func _emit_completed(result: Dictionary) -> void:
	var payload: Dictionary = result.duplicate(true)
	transaction_completed.emit(payload)
	if inventory_facade != null:
		inventory_facade.publish_transaction(payload)
