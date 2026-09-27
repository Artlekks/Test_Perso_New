extends Node
class_name FishingTradeService

signal trade_completed(
	recipe: FishingTradeRecipe,
	result: Dictionary
)

enum TradeState {
	INVALID,
	MISSING_FISH,
	OWNED_UNIQUE_REWARD,
	READY,
}

var inventory: FishingInventory = null
var tackle_catalog: FishingTackleCatalog = null
var trade_catalog: FishingTradeCatalog = null
var manillo_ledger: FishingManilloLedger = null


func configure(
	new_inventory: FishingInventory,
	new_tackle_catalog: FishingTackleCatalog,
	new_trade_catalog: FishingTradeCatalog,
	new_manillo_ledger: FishingManilloLedger = null
) -> void:
	inventory = new_inventory
	tackle_catalog = new_tackle_catalog
	trade_catalog = new_trade_catalog
	manillo_ledger = new_manillo_ledger


func evaluate_trade(
	recipe: FishingTradeRecipe
) -> Dictionary:
	var result: Dictionary = {
		"state": TradeState.INVALID,
		"state_label": "INVALID",
		"can_trade": false,
		"reason": "",
		"recipe_id": &"",
		"shop_id": &"",
		"shop_name": "",
		"missing_fish": {},
		"costs": {},
		"reward_type": -1,
		"reward_id": &"",
		"reward_quantity": 0,
		"reward": null,
		"unique_reward": false,
		"reward_already_owned": false,
		"manillo_value_units": 0,
		"manillo_value_display": 0.0,
	}

	if inventory == null:
		result["reason"] = "inventory_unavailable"
		return result

	if tackle_catalog == null:
		result["reason"] = "tackle_catalog_unavailable"
		return result

	if (
		recipe == null
		or not recipe.is_valid_definition()
	):
		result["reason"] = "invalid_recipe"
		return result

	var reward: Resource = _resolve_reward(
		recipe
	)

	result["recipe_id"] = recipe.recipe_id
	result["shop_id"] = recipe.shop_id
	result["shop_name"] = recipe.shop_name
	result["costs"] = recipe.get_cost_dictionary()
	result["reward_type"] = recipe.reward_type
	result["reward_id"] = recipe.reward_id
	result["reward_quantity"] = recipe.reward_quantity
	result["reward"] = reward
	result["unique_reward"] = recipe.unique_reward
	result["manillo_value_units"] = (
		recipe.manillo_value_units
	)
	result["manillo_value_display"] = (
		recipe.get_manillo_value_display()
	)

	if reward == null:
		result["reason"] = "unknown_reward"
		return result

	var reward_already_owned: bool = (
		_is_unique_reward_owned(
			recipe
		)
	)
	result["reward_already_owned"] = (
		reward_already_owned
	)

	if reward_already_owned:
		result["state"] = (
			TradeState.OWNED_UNIQUE_REWARD
		)
		result["state_label"] = "OWNED"
		result["reason"] = (
			"already_owned_unique_reward"
		)
		return result

	var plan: Dictionary = inventory.plan_fish_costs(
		recipe.required_fish_ids,
		recipe.required_counts
	)
	var missing: Dictionary = (
		plan.get(
			"missing_fish",
			{}
		) as Dictionary
	).duplicate(true)

	result["missing_fish"] = missing

	if not missing.is_empty():
		result["state"] = TradeState.MISSING_FISH
		result["state_label"] = "MISSING_FISH"
		result["reason"] = "missing_fish"
		return result

	result["state"] = TradeState.READY
	result["state_label"] = "READY"
	result["can_trade"] = true
	result["reason"] = "ok"
	return result


func execute_trade(
	recipe: FishingTradeRecipe
) -> Dictionary:
	var result: Dictionary = evaluate_trade(
		recipe
	)

	if not bool(
		result.get(
			"can_trade",
			false
		)
	):
		return result

	# All mutable trade state (physical fish, tackle and Manillo balance) is
	# stored in FishingInventory. One snapshot gives us a deterministic rollback
	# point and one final commit writes the completed exchange.
	var snapshot: Dictionary = (
		inventory.create_transaction_snapshot()
	)

	var consumption: Dictionary = (
		inventory.consume_fish_costs(
			recipe.required_fish_ids,
			recipe.required_counts,
			false
		)
	)

	if not bool(
		consumption.get(
			"success",
			false
		)
	):
		inventory.restore_transaction_snapshot(
			snapshot
		)
		result["can_trade"] = false
		result["state"] = TradeState.MISSING_FISH
		result["state_label"] = "MISSING_FISH"
		result["reason"] = "inventory_changed"
		result["missing_fish"] = (
			consumption.get(
				"missing_fish",
				{}
			)
		)
		return result

	var grant_result: Dictionary = (
		_grant_reward(
			recipe
		)
	)

	if not bool(
		grant_result.get(
			"granted",
			false
		)
	):
		inventory.restore_transaction_snapshot(
			snapshot
		)
		result["can_trade"] = false
		result["state"] = TradeState.INVALID
		result["state_label"] = "INVALID"
		result["reason"] = str(
			grant_result.get(
				"reason",
				"reward_grant_failed"
			)
		)
		return result

	if (
		manillo_ledger != null
		and recipe.manillo_value_units > 0
	):
		manillo_ledger.add_trade_value_units(
			recipe.manillo_value_units,
			false
		)

	if not inventory.commit_changes():
		inventory.restore_transaction_snapshot(
			snapshot
		)
		result["can_trade"] = false
		result["state"] = TradeState.INVALID
		result["state_label"] = "INVALID"
		result["reason"] = "inventory_save_failed"
		return result

	result["reason"] = "completed"
	result["state"] = TradeState.READY
	result["state_label"] = "COMPLETED"
	result["reward_count_after"] = int(
		grant_result.get(
			"count_after",
			0
		)
	)
	result["consumed_specimens"] = (
		consumption.get(
			"consumed_specimens",
			{}
		)
	)
	result["fish_counts_after"] = (
		inventory.get_all_fish_counts()
	)
	result["manillo_balance"] = (
		manillo_ledger.get_summary()
		if manillo_ledger != null
		else {}
	)

	trade_completed.emit(
		recipe,
		result.duplicate(true)
	)
	return result


func get_all_recipes() -> Array[FishingTradeRecipe]:
	if trade_catalog == null:
		return []

	return trade_catalog.get_all_recipes()


func get_recipe_by_id(
	recipe_id: StringName
) -> FishingTradeRecipe:
	if trade_catalog == null:
		return null

	return trade_catalog.get_recipe_by_id(
		recipe_id
	)


func get_recipes_for_shop_id(
	shop_id: StringName
) -> Array[FishingTradeRecipe]:
	if trade_catalog == null:
		return []

	return trade_catalog.get_recipes_for_shop_id(
		shop_id
	)


func get_recipes_for_shop(
	shop_name: String
) -> Array[FishingTradeRecipe]:
	if trade_catalog == null:
		return []

	return trade_catalog.get_recipes_for_shop(
		shop_name
	)


func get_trade_statuses_for_shop(
	shop_id: StringName
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for recipe in get_recipes_for_shop_id(
		shop_id
	):
		result.append(
			evaluate_trade(
				recipe
			)
		)

	return result


func get_affordable_trade_count(
	shop_id: StringName = &""
) -> int:
	var count: int = 0
	var recipes_to_check: Array[FishingTradeRecipe] = (
		get_all_recipes()
		if shop_id == &""
		else get_recipes_for_shop_id(shop_id)
	)

	for recipe in recipes_to_check:
		if bool(
			evaluate_trade(recipe).get(
				"can_trade",
				false
			)
		):
			count += 1

	return count


func get_debug_summary() -> String:
	if trade_catalog == null:
		return "NO TRADE CATALOG"

	return "%s | %d affordable" % [
		trade_catalog.get_debug_summary(),
		get_affordable_trade_count(),
	]


func _resolve_reward(
	recipe: FishingTradeRecipe
) -> Resource:
	match recipe.reward_type:
		FishingTradeRecipe.RewardType.LURE:
			return tackle_catalog.get_lure_by_id(
				recipe.reward_id
			)

		FishingTradeRecipe.RewardType.ROD:
			return tackle_catalog.get_rod_by_id(
				recipe.reward_id
			)

		_:
			return null


func _is_unique_reward_owned(
	recipe: FishingTradeRecipe
) -> bool:
	if not recipe.unique_reward:
		return false

	match recipe.reward_type:
		FishingTradeRecipe.RewardType.ROD:
			return inventory.owns_rod(
				recipe.reward_id
			)

		FishingTradeRecipe.RewardType.LURE:
			return inventory.owns_lure(
				recipe.reward_id
			)

		_:
			return false


func _grant_reward(
	recipe: FishingTradeRecipe
) -> Dictionary:
	var result: Dictionary = {
		"granted": false,
		"reason": "",
		"count_after": 0,
	}

	match recipe.reward_type:
		FishingTradeRecipe.RewardType.LURE:
			var lure_count_after: int = (
				inventory.grant_lure(
					recipe.reward_id,
					recipe.reward_quantity,
					false
				)
			)
			result["granted"] = (
				lure_count_after > 0
			)
			result["count_after"] = (
				lure_count_after
			)

		FishingTradeRecipe.RewardType.ROD:
			if (
				recipe.unique_reward
				and inventory.owns_rod(
					recipe.reward_id
				)
			):
				result["reason"] = (
					"already_owned_unique_reward"
				)
				return result

			var rod_count_after: int = (
				inventory.grant_rod(
					recipe.reward_id,
					recipe.reward_quantity,
					false
				)
			)
			result["granted"] = (
				rod_count_after > 0
			)
			result["count_after"] = (
				rod_count_after
			)

		_:
			result["reason"] = (
				"invalid_reward_type"
			)

	if (
		not bool(
			result.get(
				"granted",
				false
			)
		)
		and str(
			result.get(
				"reason",
				""
			)
		).is_empty()
	):
		result["reason"] = "grant_failed"

	return result
