extends RefCounted

## Read-only simulator adapter. No scenes, saves, unlocks or transactions are changed.
const World = preload("res://scripts/world/world_location_service.gd")
const Content = preload("res://data/bof4/catalogs/all_content.tres")
const Shops = preload("res://data/bof4/shops/all_shops.tres")
const Trades = preload("res://data/bof4/trades/all_trades.tres")
const Config = preload("res://data/economy/economy_foundation_v1.tres")
const PlanPath = "res://data/progression/early_tackle_acquisition_v1.json"
var _provider_validity: Dictionary = {}
var _provider_contexts: Dictionary = {}

func provider_exists(location, path: String) -> bool:
	var key := "%s:%s" % [location.location_id, path]
	if not _provider_validity.has(key):
		var packed = load(location.scene_path)
		var scene = packed.instantiate() if packed is PackedScene else null
		var provider = scene.get_node_or_null(NodePath(path)) if scene != null else null
		_provider_validity[key] = provider != null
		_provider_contexts[key] = provider.get("economy_context") if provider != null else null
		if scene != null:
			scene.free()
	return _provider_validity[key]

class Ownership:
	extends RefCounted
	var acquired: Dictionary
	func owns_lure(id: StringName) -> bool:
		return id == FishingInventory.STARTER_LURE_ID or acquired.has(String(id))
	func owns_rod(id: StringName) -> bool:
		return id == FishingInventory.STARTER_ROD_ID or acquired.has(String(id))

func targets() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(PlanPath)).targets

func price(source_id: StringName) -> int:
	var offer = Shops.get_offer_by_id(source_id)
	return Config.get_offer_buy_price(offer.item_type, offer.item_id, offer.price_zenny) if offer != null else -1

func source_matches(context, purchase: Dictionary) -> bool:
	if context == null or context.full_catalog_access:
		return false
	if purchase.source_type == "shop_offer":
		var offer = Shops.get_offer_by_id(StringName(purchase.source_id))
		return offer != null and context.shop_ids.has(String(offer.shop_id)) and (offer.availability_tag == &"" or bool(context.availability.get(offer.availability_tag, context.availability.get(String(offer.availability_tag), false))))
	var recipe = Trades.get_recipe_by_id(StringName(purchase.source_id))
	return recipe != null and context.trade_shop_ids.has(String(recipe.shop_id)) and (context.trade_recipe_ids.is_empty() or context.trade_recipe_ids.has(String(recipe.recipe_id)))

func reachable(acquired: Dictionary, origin: StringName = &"beach") -> Dictionary:
	var inventory := Ownership.new()
	inventory.acquired = acquired
	var world := World.new()
	world.current_location = world.get_location(origin)
	var result := world.get_reachable_world_data(inventory)
	world.free()
	return result

func available(purchase: Dictionary, acquired: Dictionary, origin: StringName = &"beach") -> bool:
	return source_location(purchase, acquired, origin) != &""

func source_location(purchase: Dictionary, acquired: Dictionary, origin: StringName) -> StringName:
	for source in reachable(acquired, origin).sources:
		var parts: PackedStringArray = String(source.path).split(":", true, 1)
		if parts.size() != 2:
			continue
		var location = null
		for candidate in World.LOCATION_REGISTRY.locations:
			if String(candidate.location_id) == parts[0]:
				location = candidate
				break
		if location != null and provider_exists(location, parts[1]) and _provider_contexts[source.path] == source.context and source_matches(source.context, purchase):
			return location.location_id
	return &""

func population(purchase: Dictionary, acquired: Dictionary, bank: Dictionary, origin: StringName = &"beach") -> Dictionary:
	var reachable_data := reachable(acquired, origin)
	var wanted := ""
	var deficit := 0.0
	for species in purchase.get("fish_requirements", {}):
		var missing := float(purchase.fish_requirements[species]) - float(bank.get(species, 0.0))
		if missing > deficit:
			deficit = missing
			wanted = species
	var spot = null
	var fishing_location := ""
	for location in World.LOCATION_REGISTRY.locations:
		if location.location_id == origin and reachable_data.location_ids.has(String(origin)):
			spot = location.fishing_spot
			fishing_location = String(origin)
	for candidate in reachable_data.spots:
		for entry in candidate.fish_population:
			if entry.fish != null and entry.fish.get_stable_species_id() == wanted and entry.get_base_bite_weight() > 0.0:
				spot = candidate
				for location in World.LOCATION_REGISTRY.locations:
					if location.fishing_spot == spot and reachable_data.location_ids.has(String(location.location_id)):
						fishing_location = String(location.location_id)
				break
	if spot == null:
		return {"spot_id": "", "weights": {}, "location_id": "", "reachable_location_ids": reachable_data.location_ids, "source_issues": reachable_data.source_issues}
	var lure = Content.tackle.get_lure_by_id(FishingInventory.STARTER_LURE_ID)
	var depth := 0.5
	var target = Content.get_fish_by_id(StringName(wanted))
	if target != null:
		depth = (target.preferred_depth_min + target.preferred_depth_max) * 0.5
		for id in acquired:
			var candidate = Content.tackle.get_lure_by_id(StringName(id))
			if candidate != null and target.get_lure_match_multiplier(candidate, true) > target.get_lure_match_multiplier(lure, true):
				lure = candidate
	var weights := {}
	for entry in spot.fish_population:
		var weight: float = entry.get_bite_selection_weight(lure, depth, 1.0, true)
		if weight > 0.0:
			weights[entry.fish.get_stable_species_id()] = weight
	return {"spot_id": String(spot.spot_id), "location_id": fishing_location, "weights": weights, "lure_id": String(lure.lure_id), "depth_ratio": depth, "reachable_location_ids": reachable_data.location_ids, "source_issues": reachable_data.source_issues}

func audit() -> Dictionary:
	var issues: Array = []
	var chain: Array = []
	for location in World.LOCATION_REGISTRY.locations:
		if location.economy_contexts.size() != location.economy_provider_paths.size():
			issues.append({"location_id": String(location.location_id), "reason": "provider_metadata_missing", "contexts": location.economy_contexts.size(), "providers": location.economy_provider_paths.size()})
		if location.location_id != &"beach" and location.destinations.is_empty():
			issues.append({"location_id": String(location.location_id), "reason": "no_outbound_routes"})
		if location.unlock_hint.begins_with("Requires") and location.required_lure_ids.is_empty() and location.required_rod_ids.is_empty():
			issues.append({"location_id": String(location.location_id), "reason": "unlock_hint_without_equipment_gate"})
		for index in location.economy_provider_paths.size():
			var path: String = location.economy_provider_paths[index]
			if path.is_empty() or not provider_exists(location, path):
				issues.append({"location_id": String(location.location_id), "reason": "provider_node_missing", "path": path})
			elif index >= location.economy_contexts.size() or _provider_contexts["%s:%s" % [location.location_id, path]] != location.economy_contexts[index]:
				issues.append({"location_id": String(location.location_id), "reason": "provider_context_mismatch", "path": path})
	for target in targets():
		var row: Dictionary = target.duplicate(true)
		row.locations = []
		for location in World.LOCATION_REGISTRY.locations:
			for context in location.economy_contexts:
				if source_matches(context, target):
					row.locations.append({"location_id": String(location.location_id), "required_lures": location.required_lure_ids, "required_rods": location.required_rod_ids})
		if target.source_type == "shop_offer":
			row.price_zenny = price(StringName(target.source_id))
		else:
			row.fish_requirements = Trades.get_recipe_by_id(StringName(target.source_id)).get_cost_dictionary()
		chain.append(row)
	return {"issues": issues, "chain": chain}
