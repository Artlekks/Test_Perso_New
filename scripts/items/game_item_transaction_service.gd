extends Node
class_name GameItemTransactionService

const SaveStorage = preload("res://scripts/fishing_save_storage.gd")
const SALE_JOURNAL_VERSION := 1
const DEFAULT_SALE_JOURNAL_PATH := "user://item_sale_pending.json"
const SALE_JOURNAL_KEYS = {"store": "cross_store_journal", 1: ["version", "transaction_id", "item_save_path", "wallet_save_path", "player_before", "player_after", "wallet_before", "wallet_after"]}

signal transaction_completed(result: Dictionary)

var item_catalog: GameItemCatalogService = null
var player_inventory: PlayerItemInventory = null
var inventory_facade: GameInventoryFacade = null
var fishing_inventory: FishingInventory = null
var _sale_journal_path: String = DEFAULT_SALE_JOURNAL_PATH
var _sale_transaction_counter: int = 0


func configure_sale_journal_path(path: String) -> void:
	if path.begins_with("user://") and path.ends_with(".json"):
		_sale_journal_path = path


func get_cross_store_journal_path() -> String:
	return _sale_journal_path


func has_pending_catch_transaction() -> bool:
	return _catch_journal_pending()


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
	if player_inventory != null and fishing_inventory != null:
		SaveStorage.register_cross_store_journal(_sale_journal_path,
			player_inventory.get_save_path(), fishing_inventory.get_save_path(),
			SALE_JOURNAL_KEYS)
		recover_pending_sale()


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
	if persist and has_pending_sale():
		return {"success": false, "reason": "pending_transaction_unresolved"}
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
	if persist and has_pending_sale():
		result["reason"] = "pending_transaction_unresolved"
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
	if persist and has_pending_sale():
		return {"success": false, "reason": "pending_transaction_unresolved"}
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


## Atomic bridge for recipes that consume physical fish plus generic player
## items and produce generic player items. Prepared bait uses this now; the same
## boundary can later support a fish-driven Card Maker without duplicating
## rollback or notification logic.
func exchange_fish_and_player_items(
	fish_costs: Dictionary,
	player_costs: Dictionary,
	player_rewards: Dictionary,
	persist: bool = true,
	context: StringName = &""
) -> Dictionary:
	var result := {
		"success": false,
		"reason": "",
		"context": String(context),
		"consumed_fish": {},
		"consumed_player_items": {},
		"granted_player_items": {},
	}
	if (
		item_catalog == null
		or player_inventory == null
		or fishing_inventory == null
	):
		result["reason"] = "item_backend_unavailable"
		return result
	if persist and has_pending_sale():
		var recovery := recover_pending_sale()
		result["reason"] = "pending_transaction_recovered" if bool(recovery.get("recovered", false)) and not has_pending_sale() else "pending_transaction_unresolved"
		result["pending_transaction_id"] = recovery.get("transaction_id", "")
		return result
	if persist and _catch_journal_pending():
		result["reason"] = "pending_catch_unresolved"
		return result
	if persist and _card_maker_journal_pending():
		result["reason"] = "pending_card_maker_unresolved"
		return result
	if persist and not _ensure_sale_baseline():
		result["reason"] = "exchange_store_unavailable"
		return result
	var durable_before := _disk_sale_state() if persist else {}
	if persist and durable_before.status != "valid":
		result["reason"] = "exchange_store_unavailable"
		return result

	var fish_species_ids := PackedStringArray()
	var fish_counts := PackedInt32Array()
	for raw_species_id in fish_costs.keys():
		var species_id := StringName(str(raw_species_id))
		var amount: int = maxi(0, int(fish_costs[raw_species_id]))
		if amount <= 0:
			continue
		var fish_definition: GameItemDefinition = item_catalog.get_by_domain(
			GameItemCatalogService.STORAGE_FISH,
			species_id
		)
		if fish_definition == null:
			result["reason"] = "unknown_fish"
			result["unknown_species_id"] = String(species_id)
			return result
		fish_species_ids.append(String(species_id))
		fish_counts.append(amount)

	var fish_plan: Dictionary = fishing_inventory.plan_fish_costs(
		fish_species_ids,
		fish_counts
	)
	if not bool(fish_plan.get("can_afford", false)):
		result["reason"] = "missing_fish"
		var missing_fish: Dictionary = fish_plan.get("missing_fish", {})
		result["missing_fish"] = missing_fish.duplicate(true)
		return result

	var player_cost_evaluation: Dictionary = evaluate_player_costs(
		player_costs
	)
	if not bool(player_cost_evaluation.get("can_afford", false)):
		result["reason"] = str(
			player_cost_evaluation.get("reason", "missing_items")
		)
		var missing_items: Dictionary = player_cost_evaluation.get(
			"missing",
			{}
		)
		result["missing_player_items"] = missing_items.duplicate(true)
		return result

	var normalized_rewards: Dictionary = {}
	for raw_id in player_rewards.keys():
		var reward_item_id := StringName(str(raw_id))
		var reward_amount: int = maxi(0, int(player_rewards[raw_id]))
		if reward_amount <= 0:
			continue
		var reward_definition: GameItemDefinition = item_catalog.get_definition(
			reward_item_id
		)
		if reward_definition == null:
			result["reason"] = "unknown_item"
			result["unknown_item_id"] = String(reward_item_id)
			return result
		if (
			reward_definition.storage_kind
			!= GameItemCatalogService.STORAGE_PLAYER
		):
			result["reason"] = "non_player_storage_reward"
			result["unsupported_item_id"] = String(reward_item_id)
			return result
		normalized_rewards[String(reward_item_id)] = reward_amount

	var player_snapshot: Dictionary = player_inventory.create_transaction_snapshot()
	var fishing_snapshot: Dictionary = fishing_inventory.create_transaction_snapshot()
	_begin_cross_inventory_notifications()

	var fish_result: Dictionary = fishing_inventory.consume_fish_costs(
		fish_species_ids,
		fish_counts,
		false
	)
	if not bool(fish_result.get("success", false)):
		_rollback_cross_inventory_exchange(
			player_snapshot,
			fishing_snapshot,
			false
		)
		result["reason"] = "fish_inventory_changed"
		return result

	var player_consume: Dictionary = player_inventory.consume_costs(
		player_cost_evaluation.get("normalized_costs", {}),
		false
	)
	if not bool(player_consume.get("success", false)):
		_rollback_cross_inventory_exchange(
			player_snapshot,
			fishing_snapshot,
			false
		)
		result["reason"] = "player_inventory_changed"
		return result

	for raw_id in normalized_rewards.keys():
		player_inventory.grant(
			StringName(str(raw_id)),
			int(normalized_rewards[raw_id]),
			false
		)

	if persist:
		var normalized_fish_costs: Dictionary = {}
		for index in range(fish_species_ids.size()):
			normalized_fish_costs[String(fish_species_ids[index])] = int(fish_counts[index])
		var transaction_id := _new_sale_transaction_id()
		var intent := {
			"version": SALE_JOURNAL_VERSION,
			"kind": "mixed_exchange",
			"transaction_id": transaction_id,
			"item_save_path": player_inventory.get_save_path(),
			"wallet_save_path": fishing_inventory.get_save_path(),
			"fish_costs": normalized_fish_costs,
			"player_costs": player_cost_evaluation.get("normalized_costs", {}).duplicate(true),
			"player_rewards": normalized_rewards.duplicate(true),
			"consumed_fish": fish_result.get("consumed_specimens", {}).duplicate(true),
			"player_before": durable_before.player,
			"player_after": player_inventory.create_transaction_snapshot(),
			"wallet_before": durable_before.wallet,
			"wallet_after": fishing_inventory.create_transaction_snapshot(),
		}
		_qa_mixed_pause("before_intent")
		if not SaveStorage.write(_sale_journal_path, intent,
			SALE_JOURNAL_VERSION, SALE_JOURNAL_KEYS):
			player_inventory.restore_transaction_snapshot(player_snapshot, false)
			fishing_inventory.restore_transaction_snapshot(fishing_snapshot)
			_cancel_cross_inventory_notifications()
			result["reason"] = "pending_transaction_unresolved" if has_pending_sale() else "exchange_journal_write_failed"
			if has_pending_sale():
				result["pending_transaction_id"] = transaction_id
			return result
		result["transaction_id"] = transaction_id
		_qa_mixed_pause("after_intent")
		SaveStorage.begin_cross_store_write(_sale_journal_path, transaction_id)
		var item_saved := not _qa_mixed_failure("fail_item_commit") and player_inventory.commit_changes()
		SaveStorage.end_cross_store_write()
		if not item_saved:
			_cancel_cross_inventory_notifications()
			_sync_sale_stores()
			result["reason"] = "item_save_failed"
			return result
		_qa_mixed_pause("after_item_commit")
		SaveStorage.begin_cross_store_write(_sale_journal_path, transaction_id)
		var fish_saved := not _qa_mixed_failure("fail_fish_commit") and fishing_inventory.commit_changes()
		SaveStorage.end_cross_store_write()
		if not fish_saved:
			_cancel_cross_inventory_notifications()
			_sync_sale_stores()
			result["reason"] = "fish_save_failed"
			return result
		_qa_mixed_pause("after_fish_commit")
		var committed := _disk_sale_state()
		if committed.status != "valid" or _sale_phase(committed.player, intent.player_before, intent.player_after) != "after" or _sale_phase(committed.wallet, intent.wallet_before, intent.wallet_after) != "after":
			_cancel_cross_inventory_notifications()
			_sync_sale_stores()
			result["reason"] = "exchange_commit_unverified"
			return result
		_qa_mixed_pause("before_cleanup")
		result["journal_cleanup_pending"] = not _clear_sale_journal()

	var consumed_fish: Dictionary = fish_result.get(
		"consumed_specimens",
		{}
	)
	var consumed_player: Dictionary = player_consume.get("consumed", {})
	result["success"] = true
	result["reason"] = "completed"
	result["consumed_fish"] = consumed_fish.duplicate(true)
	result["consumed_player_items"] = consumed_player.duplicate(true)
	result["granted_player_items"] = normalized_rewards.duplicate(true)
	_commit_cross_inventory_notifications()
	_emit_completed(result)
	return result


func _rollback_cross_inventory_exchange(
	player_snapshot: Dictionary,
	fishing_snapshot: Dictionary,
	rewrite_disk: bool
) -> void:
	player_inventory.restore_transaction_snapshot(
		player_snapshot,
		false
	)
	fishing_inventory.restore_transaction_snapshot(
		fishing_snapshot
	)
	if rewrite_disk:
		player_inventory.save_to_disk()
		fishing_inventory.save_to_disk()
	_cancel_cross_inventory_notifications()


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
	if persist:
		return _persist_item_sale(result, item_id, amount, unit_value_zenny)
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

	result["success"] = true
	result["reason"] = "completed"
	result["remaining_count"] = player_inventory.get_count(item_id)
	result["zenny_after"] = fishing_inventory.get_zenny()
	result["consumed"] = consumed.get("consumed", {}).duplicate(true)
	_commit_cross_inventory_notifications()
	_emit_completed(result)
	return result


func has_pending_sale() -> bool:
	return SaveStorage.read(_sale_journal_path, SALE_JOURNAL_VERSION,
		SALE_JOURNAL_KEYS).status != "new"


func recover_pending_sale() -> Dictionary:
	var pending: Dictionary = SaveStorage.read(_sale_journal_path,
		SALE_JOURNAL_VERSION, SALE_JOURNAL_KEYS)
	if pending.status == "new":
		return {"recovered": true, "reason": "nothing_pending"}
	if pending.status != "valid":
		return {"recovered": false, "reason": "invalid_or_unsupported_sale_journal"}
	if player_inventory == null or fishing_inventory == null:
		return {"recovered": false, "reason": "item_backend_unavailable"}
	var intent: Dictionary = pending.data
	var transaction_id: String = str(intent["transaction_id"])
	if intent.get("kind", "sale") == "beach_craft":
		return {"recovered": false, "reason": "beach_craft_recovery_required",
			"transaction_id": transaction_id}
	var mixed: bool = intent.get("kind", "sale") == "mixed_exchange"
	if _catch_journal_pending():
		return {"recovered": false, "reason": "pending_catch_unresolved",
			"transaction_id": transaction_id}
	if _card_maker_journal_pending():
		return {"recovered": false, "reason": "pending_card_maker_unresolved",
			"transaction_id": transaction_id}
	if intent["item_save_path"] != player_inventory.get_save_path() or intent["wallet_save_path"] != fishing_inventory.get_save_path():
		return {"recovered": false, "reason": "sale_journal_store_mismatch",
			"transaction_id": transaction_id}
	var disk: Dictionary = _disk_sale_state()
	if disk.status != "valid":
		return {"recovered": false, "reason": "sale_store_unavailable",
			"transaction_id": transaction_id}
	var player_phase := _sale_phase(disk.player, intent.player_before,
		intent.player_after)
	var wallet_phase := _sale_phase(disk.wallet, intent.wallet_before,
		intent.wallet_after)
	if player_phase == "unknown" or wallet_phase == "unknown" or (player_phase == "before" and wallet_phase == "after"):
		return {"recovered": false, "reason": "sale_state_ambiguous",
			"transaction_id": transaction_id}
	if player_phase == "before":
		var item_copy: PlayerItemInventory = PlayerItemInventory.new()
		item_copy.configure(player_inventory.get_save_path())
		if not item_copy.load_from_disk():
			item_copy.free()
			return {"recovered": false, "reason": "item_recovery_load_failed",
				"transaction_id": transaction_id}
		item_copy.restore_transaction_snapshot(intent.player_after, false)
		SaveStorage.begin_cross_store_write(_sale_journal_path, transaction_id)
		var item_saved := not (_qa_mixed_failure("fail_item_recovery") if mixed else _qa_sale_failure("fail_item_recovery")) and item_copy.save_to_disk()
		SaveStorage.end_cross_store_write()
		item_copy.free()
		if not item_saved:
			return {"recovered": false, "reason": "item_recovery_save_failed",
				"transaction_id": transaction_id}
	if wallet_phase == "before":
		var wallet_copy: FishingInventory = FishingInventory.new()
		wallet_copy.configure_save_path(fishing_inventory.get_save_path())
		if not wallet_copy.load_from_disk():
			wallet_copy.free()
			return {"recovered": false, "reason": "wallet_recovery_load_failed",
				"transaction_id": transaction_id}
		wallet_copy.restore_transaction_snapshot(intent.wallet_after)
		SaveStorage.begin_cross_store_write(_sale_journal_path, transaction_id)
		var wallet_saved := not (_qa_mixed_failure("fail_fish_recovery") if mixed else _qa_sale_failure("fail_wallet_recovery")) and wallet_copy.save_to_disk()
		SaveStorage.end_cross_store_write()
		wallet_copy.free()
		if not wallet_saved:
			return {"recovered": false, "reason": "wallet_recovery_save_failed",
				"transaction_id": transaction_id}
	var committed: Dictionary = _disk_sale_state()
	if committed.status != "valid" or _sale_phase(committed.player, intent.player_before, intent.player_after) != "after" or _sale_phase(committed.wallet, intent.wallet_before, intent.wallet_after) != "after":
		return {"recovered": false, "reason": "sale_commit_unverified",
			"transaction_id": transaction_id}
	_sync_sale_stores()
	if not _clear_sale_journal():
		return {"recovered": false, "reason": "sale_journal_cleanup_failed",
			"transaction_id": transaction_id}
	return {"recovered": true, "reason": "sale_completed" if not mixed else "exchange_completed",
		"kind": "mixed_exchange" if mixed else "sale",
		"transaction_id": transaction_id}


func _persist_item_sale(result: Dictionary, item_id: StringName,
	amount: int, unit_value_zenny: int) -> Dictionary:
	if has_pending_sale():
		var recovery := recover_pending_sale()
		if not bool(recovery.get("recovered", false)) or has_pending_sale():
			result["reason"] = "pending_sale_unresolved"
			result["pending_transaction_id"] = recovery.get("transaction_id", "")
			return result
		result["reason"] = "pending_sale_recovered" if recovery.get("kind", "sale") == "sale" else "pending_transaction_recovered"
		result["pending_transaction_id"] = recovery.get("transaction_id", "")
		return result
	if _catch_journal_pending():
		result["reason"] = "pending_catch_unresolved"
		return result
	if _card_maker_journal_pending():
		result["reason"] = "pending_card_maker_unresolved"
		return result
	if player_inventory.get_count(item_id) < amount:
		result["reason"] = "not_enough_items"
		return result
	if not _ensure_sale_baseline():
		result["reason"] = "sale_store_unavailable"
		return result
	var before: Dictionary = _disk_sale_state()
	if before.status != "valid":
		result["reason"] = "sale_store_unavailable"
		return result
	var total := amount * unit_value_zenny
	if total <= 0 or fishing_inventory.get_zenny() > 9223372036854775807 - total:
		result["reason"] = "invalid_sale_value"
		return result
	var player_before: Dictionary = before.player
	var wallet_before: Dictionary = before.wallet
	var player_after: Dictionary = player_before.duplicate(true)
	var after_counts: Dictionary = player_after.get("counts", {})
	var remaining: int = int(after_counts.get(String(item_id), 0)) - amount
	if remaining < 0:
		result["reason"] = "inventory_changed"
		return result
	if remaining == 0:
		after_counts.erase(String(item_id))
	else:
		after_counts[String(item_id)] = remaining
	player_after["counts"] = after_counts
	var wallet_after: Dictionary = wallet_before.duplicate(true)
	wallet_after["zenny_balance"] = int(wallet_before["zenny_balance"]) + total
	var transaction_id := _new_sale_transaction_id()
	var intent: Dictionary = {
		"version": SALE_JOURNAL_VERSION,
		"transaction_id": transaction_id,
		"item_id": String(item_id),
		"amount": amount,
		"unit_value_zenny": unit_value_zenny,
		"total_value_zenny": total,
		"item_save_path": player_inventory.get_save_path(),
		"wallet_save_path": fishing_inventory.get_save_path(),
		"player_before": player_before,
		"player_after": player_after,
		"wallet_before": wallet_before,
		"wallet_after": wallet_after,
	}
	_qa_sale_pause("before_intent")
	if not SaveStorage.write(_sale_journal_path, intent, SALE_JOURNAL_VERSION,
		SALE_JOURNAL_KEYS):
		result["reason"] = "sale_journal_write_failed"
		return result
	result["transaction_id"] = transaction_id
	_qa_sale_pause("after_intent")
	_begin_cross_inventory_notifications()
	var consumed: Dictionary = player_inventory.consume_costs(
		{String(item_id): amount}, false)
	if not bool(consumed.get("success", false)):
		_cancel_cross_inventory_notifications()
		result["reason"] = "inventory_changed"
		return result
	fishing_inventory.add_zenny(total, false)
	result["zenny_before"] = int(wallet_before["zenny_balance"])
	result["total_value_zenny"] = total
	SaveStorage.begin_cross_store_write(_sale_journal_path, transaction_id)
	var item_saved := not _qa_sale_failure("fail_item_commit") and player_inventory.commit_changes()
	SaveStorage.end_cross_store_write()
	if not item_saved:
		_cancel_cross_inventory_notifications()
		_sync_sale_stores()
		result["reason"] = "item_save_failed"
		return result
	_qa_sale_pause("after_item_commit")
	SaveStorage.begin_cross_store_write(_sale_journal_path, transaction_id)
	var wallet_saved := not _qa_sale_failure("fail_wallet_commit") and fishing_inventory.commit_changes()
	SaveStorage.end_cross_store_write()
	if not wallet_saved:
		_cancel_cross_inventory_notifications()
		_sync_sale_stores()
		result["reason"] = "wallet_save_failed"
		return result
	_qa_sale_pause("after_wallet_commit")
	var committed: Dictionary = _disk_sale_state()
	if committed.status != "valid" or _sale_phase(committed.player, player_before, player_after) != "after" or _sale_phase(committed.wallet, wallet_before, wallet_after) != "after":
		_cancel_cross_inventory_notifications()
		_sync_sale_stores()
		result["reason"] = "sale_commit_unverified"
		return result
	_qa_sale_pause("before_cleanup")
	var cleaned := _clear_sale_journal()
	result["success"] = true
	result["reason"] = "completed"
	result["remaining_count"] = player_inventory.get_count(item_id)
	result["zenny_after"] = fishing_inventory.get_zenny()
	result["consumed"] = consumed.get("consumed", {}).duplicate(true)
	result["journal_cleanup_pending"] = not cleaned
	_commit_cross_inventory_notifications()
	_emit_completed(result)
	return result


func _ensure_sale_baseline() -> bool:
	if not player_inventory.commit_changes() or not fishing_inventory.commit_changes():
		return false
	var player_state := SaveStorage.read(player_inventory.get_save_path(),
		PlayerItemInventory.SAVE_VERSION, PlayerItemInventory.SAVE_KEYS)
	if player_state.status == "new" and not player_inventory.save_to_disk():
		return false
	var wallet_state := SaveStorage.read(fishing_inventory.get_save_path(),
		FishingInventory.SAVE_VERSION, FishingInventory.SAVE_KEYS)
	if wallet_state.status == "new" and not fishing_inventory.save_to_disk():
		return false
	var disk := _disk_sale_state()
	return disk.status == "valid" and _snapshot_token(disk.player) == _snapshot_token(player_inventory.create_transaction_snapshot()) and _snapshot_token(disk.wallet) == _snapshot_token(fishing_inventory.create_transaction_snapshot())


func _disk_sale_state() -> Dictionary:
	var item_state := SaveStorage.read(player_inventory.get_save_path(),
		PlayerItemInventory.SAVE_VERSION, PlayerItemInventory.SAVE_KEYS)
	var wallet_state := SaveStorage.read(fishing_inventory.get_save_path(),
		FishingInventory.SAVE_VERSION, FishingInventory.SAVE_KEYS)
	if item_state.status != "valid" or wallet_state.status != "valid":
		return {"status": "unavailable"}
	var item_copy: PlayerItemInventory = PlayerItemInventory.new()
	item_copy.configure(player_inventory.get_save_path())
	var item_loaded := item_copy.load_from_disk()
	var wallet_copy: FishingInventory = FishingInventory.new()
	wallet_copy.configure_save_path(fishing_inventory.get_save_path())
	var wallet_loaded := wallet_copy.load_from_disk()
	var result := {"status": "unavailable"}
	if item_loaded and wallet_loaded:
		result = {"status": "valid",
			"player": item_copy.create_transaction_snapshot(),
			"wallet": wallet_copy.create_transaction_snapshot()}
	item_copy.free()
	wallet_copy.free()
	return result


func _sale_phase(actual: Dictionary, before: Dictionary,
	after: Dictionary) -> String:
	var token := _snapshot_token(actual)
	if token == _snapshot_token(after):
		return "after"
	if token == _snapshot_token(before):
		return "before"
	return "unknown"


func _snapshot_token(snapshot: Dictionary) -> String:
	var values := snapshot.duplicate(true)
	values.erase("dirty")
	return JSON.stringify(JSON.parse_string(JSON.stringify(values)))


func _sync_sale_stores() -> void:
	if player_inventory.load_from_disk():
		player_inventory.restore_transaction_snapshot(
			player_inventory.create_transaction_snapshot(), false)
	fishing_inventory.load_from_disk()


func _clear_sale_journal() -> bool:
	if _qa_sale_failure("fail_cleanup") or _qa_mixed_failure("fail_cleanup"):
		return false
	return SaveStorage.erase_known_valid(_sale_journal_path,
		SALE_JOURNAL_VERSION, SALE_JOURNAL_KEYS)


func _new_sale_transaction_id() -> String:
	_sale_transaction_counter += 1
	return "%s-%d" % [Crypto.new().generate_random_bytes(16).hex_encode(),
		_sale_transaction_counter]


func _qa_sale_failure(stage: String) -> bool:
	return not OS.get_environment("FISHING_QA_RUN_ID").is_empty() and _sale_journal_path.begins_with("user://sale_fault_qa/") and OS.get_environment("FISHING_QA_SALE_STAGE") == stage


func _qa_sale_pause(stage: String) -> void:
	if not _qa_sale_failure(stage):
		return
	var marker := FileAccess.open("user://sale_fault_qa/fault.marker", FileAccess.WRITE)
	if marker != null:
		marker.store_string(stage)
		marker.close()
	OS.delay_msec(15000)


func _qa_mixed_failure(stage: String) -> bool:
	return not OS.get_environment("FISHING_QA_RUN_ID").is_empty() and _sale_journal_path.begins_with("user://mixed_exchange_qa/") and OS.get_environment("FISHING_QA_MIXED_STAGE") == stage


func _qa_mixed_pause(stage: String) -> void:
	if not _qa_mixed_failure(stage):
		return
	var marker := FileAccess.open("user://mixed_exchange_qa/fault.marker", FileAccess.WRITE)
	if marker != null:
		marker.store_string(stage)
		marker.close()
	OS.delay_msec(15000)


func _catch_journal_pending() -> bool:
	return FileAccess.file_exists("user://fishing_catch_pending.json") or FileAccess.file_exists("user://fishing_catch_pending.tmp")


func _card_maker_journal_pending() -> bool:
	return FileAccess.file_exists("user://fishing_card_maker_pending.json") or FileAccess.file_exists("user://fishing_card_maker_pending.tmp") or (fishing_inventory != null and SaveStorage.has_pending_card_maker_for_store(fishing_inventory.get_save_path()))


func _begin_cross_inventory_notifications() -> void:
	player_inventory.begin_notification_batch()
	fishing_inventory.begin_notification_batch()


func _commit_cross_inventory_notifications() -> void:
	player_inventory.commit_notification_batch()
	fishing_inventory.commit_notification_batch()


func _cancel_cross_inventory_notifications() -> void:
	player_inventory.cancel_notification_batch()
	fishing_inventory.cancel_notification_batch()


func _emit_completed(result: Dictionary) -> void:
	var payload: Dictionary = result.duplicate(true)
	transaction_completed.emit(payload)
	if inventory_facade != null:
		inventory_facade.publish_transaction(payload)
