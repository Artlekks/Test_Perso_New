extends Node
class_name FishingTradeService

signal trade_completed(recipe: FishingTradeRecipe, result: Dictionary)

var inventory: FishingInventory = null
var tackle_catalog: FishingTackleCatalog = null
var trade_catalog: FishingTradeCatalog = null


func configure(
	new_inventory: FishingInventory,
	new_tackle_catalog: FishingTackleCatalog,
	new_trade_catalog: FishingTradeCatalog
) -> void:
	inventory = new_inventory
	tackle_catalog = new_tackle_catalog
	trade_catalog = new_trade_catalog


func evaluate_trade(recipe: FishingTradeRecipe) -> Dictionary:
	var result := {
		"can_trade": false,
		"reason": "",
		"missing_fish": {},
		"reward_type": -1,
		"reward_id": &"",
		"reward": null,
	}

	if inventory == null:
		result["reason"] = "inventory_unavailable"
		return result

	if tackle_catalog == null:
		result["reason"] = "tackle_catalog_unavailable"
		return result

	if recipe == null or not recipe.is_cost_shape_valid():
		result["reason"] = "invalid_recipe"
		return result

	var reward = _resolve_reward(recipe)
	if reward == null:
		result["reason"] = "unknown_reward"
		return result

	var missing := inventory.get_missing_fish_costs(
		recipe.required_fish_ids,
		recipe.required_counts
	)

	result["reward_type"] = recipe.reward_type
	result["reward_id"] = recipe.reward_id
	result["reward"] = reward
	result["missing_fish"] = missing

	if not missing.is_empty():
		result["reason"] = "missing_fish"
		return result

	result["can_trade"] = true
	result["reason"] = "ok"
	return result


func execute_trade(recipe: FishingTradeRecipe) -> Dictionary:
	var result := evaluate_trade(recipe)
	if not bool(result.get("can_trade", false)):
		return result

	# Evaluation above makes the transaction deterministic. Costs are consumed
	# without individual disk writes, the reward is granted, then one save commits
	# the whole exchange.
	if not inventory.try_consume_fish_costs(
		recipe.required_fish_ids,
		recipe.required_counts,
		false
	):
		result["can_trade"] = false
		result["reason"] = "inventory_changed"
		return result

	var reward_count_after := 0
	match recipe.reward_type:
		FishingTradeRecipe.RewardType.LURE:
			reward_count_after = inventory.grant_lure(recipe.reward_id, 1, false)
		FishingTradeRecipe.RewardType.ROD:
			reward_count_after = inventory.grant_rod(recipe.reward_id, 1, false)
		_:
			result["can_trade"] = false
			result["reason"] = "invalid_reward_type"
			return result

	inventory.commit_changes()
	result["reason"] = "completed"
	result["reward_count_after"] = reward_count_after
	result["fish_counts_after"] = inventory.get_all_fish_counts()
	trade_completed.emit(recipe, result.duplicate(true))
	return result


func get_all_recipes() -> Array[FishingTradeRecipe]:
	if trade_catalog == null:
		return []
	return trade_catalog.get_all_recipes()


func get_recipes_for_shop(shop_name: String) -> Array[FishingTradeRecipe]:
	if trade_catalog == null:
		return []
	return trade_catalog.get_recipes_for_shop(shop_name)


func _resolve_reward(recipe: FishingTradeRecipe):
	match recipe.reward_type:
		FishingTradeRecipe.RewardType.LURE:
			return tackle_catalog.get_lure_by_id(recipe.reward_id)
		FishingTradeRecipe.RewardType.ROD:
			return tackle_catalog.get_rod_by_id(recipe.reward_id)
		_:
			return null
