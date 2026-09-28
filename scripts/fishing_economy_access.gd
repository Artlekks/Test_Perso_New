extends Node

## Player/UI-facing façade for the fishing economy.
##
## This layer never owns persistent state. It translates the backend economy,
## trade and fish-consumable services into stable presentation snapshots and
## forwards explicit player actions. World/NPC shop code can later provide a
## narrower context without changing the economy backend or the menu.

signal changed
signal transaction_completed(result: Dictionary)

const ShopOfferScript = preload("res://scripts/database/fishing_shop_offer.gd")

var inventory = null
var economy_service = null
var trade_service = null
var fish_consumable_service = null
var modifier_service = null
var content_catalog = null
var shop_catalog = null
var trade_catalog = null

var _availability: Dictionary = {}
var _allowed_shop_ids: PackedStringArray = PackedStringArray()
var _allowed_trade_shop_ids: PackedStringArray = PackedStringArray()
var _full_catalog_access: bool = true


func configure(
	new_inventory,
	new_economy_service,
	new_trade_service,
	new_fish_consumable_service,
	new_modifier_service,
	new_content_catalog,
	new_shop_catalog,
	new_trade_catalog
) -> void:
	inventory = new_inventory
	economy_service = new_economy_service
	trade_service = new_trade_service
	fish_consumable_service = new_fish_consumable_service
	modifier_service = new_modifier_service
	content_catalog = new_content_catalog
	shop_catalog = new_shop_catalog
	trade_catalog = new_trade_catalog

	if inventory != null and inventory.has_signal("changed"):
		var callback = Callable(self, "_on_source_changed")
		if not inventory.is_connected("changed", callback):
			inventory.connect("changed", callback)

	if modifier_service != null and modifier_service.has_signal("modifiers_changed"):
		var modifier_callback = Callable(self, "_on_source_changed_with_payload")
		if not modifier_service.is_connected("modifiers_changed", modifier_callback):
			modifier_service.connect("modifiers_changed", modifier_callback)


func set_access_context(
	shop_ids: PackedStringArray = PackedStringArray(),
	trade_shop_ids: PackedStringArray = PackedStringArray(),
	availability: Dictionary = {},
	full_catalog_access: bool = false
) -> void:
	_allowed_shop_ids = shop_ids.duplicate()
	_allowed_trade_shop_ids = trade_shop_ids.duplicate()
	_availability = availability.duplicate(true)
	_full_catalog_access = full_catalog_access
	changed.emit()


func enable_vertical_slice_full_access() -> void:
	_full_catalog_access = true
	_allowed_shop_ids.clear()
	_allowed_trade_shop_ids.clear()
	changed.emit()


func get_wallet_snapshot() -> Dictionary:
	if inventory == null:
		return {
			"zenny": 0,
			"manillo_point_units": 0,
			"manillo_stamps": 0,
			"manillo_stamp_cards": 0,
		}
	return {
		"zenny": inventory.get_zenny(),
		"manillo_point_units": inventory.get_manillo_point_units(),
		"manillo_stamps": inventory.get_manillo_stamps(),
		"manillo_stamp_cards": inventory.get_manillo_stamp_cards(),
	}


func get_sell_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if inventory == null or content_catalog == null or economy_service == null:
		return result

	for fish in content_catalog.fish:
		if fish == null:
			continue
		var species_id: String = fish.get_stable_species_id()
		var count: int = inventory.get_fish_count(species_id)
		if count <= 0:
			continue
		var unit_value: int = economy_service.get_fish_sell_value(StringName(species_id))
		result.append({
			"kind": "sell",
			"id": species_id,
			"display_name": fish.fish_name,
			"owned_count": count,
			"unit_value_zenny": unit_value,
			"total_value_zenny": unit_value * count,
			"can_execute": unit_value > 0,
			"detail": "%dz each | owned %d" % [unit_value, count],
		})

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("display_name", "")).naturalnocasecmp_to(str(b.get("display_name", ""))) < 0
	)
	return result


func sell_one(species_id: StringName) -> Dictionary:
	if economy_service == null:
		return _failure("economy_unavailable")
	var result: Dictionary = economy_service.sell_fish(species_id, 1)
	transaction_completed.emit(result.duplicate(true))
	changed.emit()
	return result


func get_buy_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if economy_service == null or shop_catalog == null:
		return result

	for offer_value in shop_catalog.get_all_offers():
		var offer: ShopOfferScript = offer_value as ShopOfferScript
		if offer == null or not _shop_allowed(offer.shop_id):
			continue
		var status: Dictionary = economy_service.evaluate_purchase(offer, 1, _availability)
		var owned_count: int = 0
		if inventory != null:
			if offer.item_type == ShopOfferScript.ItemType.LURE:
				owned_count = inventory.get_lure_count(offer.item_id)
			else:
				owned_count = inventory.get_rod_count(offer.item_id)
		result.append({
			"kind": "buy",
			"id": str(offer.offer_id),
			"shop_id": str(offer.shop_id),
			"shop_name": offer.shop_name,
			"display_name": offer.item_name,
			"price_zenny": offer.price_zenny,
			"quantity": offer.quantity,
			"owned_count": owned_count,
			"state_label": str(status.get("state_label", "INVALID")),
			"reason": str(status.get("reason", "")),
			"can_execute": bool(status.get("can_purchase", false)),
			"detail": "%s | %dz | owned %d" % [offer.shop_name, offer.price_zenny, owned_count],
		})
	return result


func buy_one(offer_id: StringName) -> Dictionary:
	if economy_service == null:
		return _failure("economy_unavailable")
	var offer: ShopOfferScript = economy_service.get_offer_by_id(offer_id)
	if offer == null:
		return _failure("unknown_offer")
	if not _shop_allowed(offer.shop_id):
		return _failure("shop_not_available")
	var result: Dictionary = economy_service.purchase_offer(offer, 1, _availability)
	transaction_completed.emit(result.duplicate(true))
	changed.emit()
	return result


func get_trade_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if trade_service == null or trade_catalog == null:
		return result

	for recipe in trade_catalog.get_all_recipes():
		if recipe == null or not _trade_shop_allowed(recipe.shop_id):
			continue
		var status: Dictionary = trade_service.evaluate_trade(recipe)
		result.append({
			"kind": "trade",
			"id": str(recipe.recipe_id),
			"shop_id": str(recipe.shop_id),
			"shop_name": recipe.shop_name,
			"display_name": recipe.reward_item,
			"reward_quantity": recipe.reward_quantity,
			"cost_text": _format_trade_costs(recipe.get_cost_dictionary()),
			"manillo_value": float(status.get("manillo_value_display", 0.0)),
			"state_label": str(status.get("state_label", "INVALID")),
			"reason": str(status.get("reason", "")),
			"can_execute": bool(status.get("can_trade", false)),
			"detail": "%s | %s" % [recipe.shop_name, _format_trade_costs(recipe.get_cost_dictionary())],
		})
	return result


func trade_one(recipe_id: StringName) -> Dictionary:
	if trade_service == null:
		return _failure("trade_service_unavailable")
	var recipe = trade_service.get_recipe_by_id(recipe_id)
	if recipe == null:
		return _failure("unknown_recipe")
	if not _trade_shop_allowed(recipe.shop_id):
		return _failure("shop_not_available")
	var result: Dictionary = trade_service.execute_trade(recipe)
	transaction_completed.emit(result.duplicate(true))
	changed.emit()
	return result


func get_use_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if inventory == null or content_catalog == null or fish_consumable_service == null:
		return result

	for fish in content_catalog.fish:
		if fish == null:
			continue
		var species_id: String = fish.get_stable_species_id()
		var count: int = inventory.get_fish_count(species_id)
		if count <= 0:
			continue
		var effect: Dictionary = fish_consumable_service.get_effect_preview(species_id)
		if effect.is_empty():
			continue
		result.append({
			"kind": "use",
			"id": species_id,
			"display_name": fish.fish_name,
			"owned_count": count,
			"effect_name": str(effect.get("display_name", "")),
			"effect_description": str(effect.get("description", "")),
			"duration_seconds": float(effect.get("duration_seconds", 0.0)),
			"can_execute": true,
			"detail": "%s | owned %d" % [str(effect.get("display_name", "Effect")), count],
		})

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("display_name", "")).naturalnocasecmp_to(str(b.get("display_name", ""))) < 0
	)
	return result


func use_one(species_id: String) -> Dictionary:
	if fish_consumable_service == null:
		return _failure("consumable_service_unavailable")
	var result: Dictionary = fish_consumable_service.use_fish(species_id, -1, true)
	transaction_completed.emit(result.duplicate(true))
	changed.emit()
	return result


func get_active_effects() -> Array[Dictionary]:
	if modifier_service == null:
		return []
	return modifier_service.get_active_effects()


func _format_trade_costs(costs: Dictionary) -> String:
	var parts = PackedStringArray()
	for raw_species_id in costs.keys():
		var species_id: String = str(raw_species_id)
		var name: String = species_id
		if content_catalog != null:
			var fish = content_catalog.get_fish_by_id(StringName(species_id))
			if fish != null:
				name = fish.fish_name
		parts.append("%s x%d" % [name, int(costs[raw_species_id])])
	return ", ".join(parts)


func _shop_allowed(shop_id: StringName) -> bool:
	return _full_catalog_access or _allowed_shop_ids.has(str(shop_id))


func _trade_shop_allowed(shop_id: StringName) -> bool:
	return _full_catalog_access or _allowed_trade_shop_ids.has(str(shop_id))


func _failure(reason: String) -> Dictionary:
	return {
		"success": false,
		"reason": reason,
	}


func _on_source_changed() -> void:
	changed.emit()


func _on_source_changed_with_payload(_payload: Dictionary) -> void:
	changed.emit()
