extends RefCounted

## Read-only ownership ladder. World providers supply their existing contextual
## economy Resource; this never applies access, spends fish, or grants equipment.
const PLAN_PATH := "res://data/progression/early_tackle_acquisition_v1.json"
const ContextScript = preload("res://scripts/economy/merchant_economy_context.gd")
var _plan: Dictionary = {}
var _inventory: FishingInventory
var _economy: FishingEconomyService
var _content: FishingContentCatalog
var _shops
var _trades

func configure(inventory: FishingInventory, economy: FishingEconomyService, content: FishingContentCatalog, shops, trades) -> void:
	_inventory = inventory
	_economy = economy
	_content = content
	_shops = shops
	_trades = trades
	_plan = JSON.parse_string(FileAccess.get_file_as_string(PLAN_PATH))

func get_snapshot(world_sources: Array = [], playable_spots: Array = []) -> Dictionary:
	var targets: Array[Dictionary] = []
	var next: Dictionary = {}
	for definition: Dictionary in _plan.get("targets", []):
		var row := _target_snapshot(definition, world_sources, playable_spots)
		targets.append(row)
		if next.is_empty() and not row.complete:
			next = row.duplicate(true)
	return {"plan_id": _plan.get("plan_id", ""), "targets": targets, "next_target": next, "complete": not targets.is_empty() and next.is_empty()}

func _target_snapshot(definition: Dictionary, sources: Array, spots: Array) -> Dictionary:
	var row := definition.duplicate(true)
	var id := StringName(row.item_id)
	var owned := 0
	if _inventory != null:
		owned = _inventory.get_rod_count(id) if row.kind == "rod" else _inventory.get_lure_count(id)
	row.merge({"owned": owned, "complete": owned > 0, "source_exists": false, "accessible": false, "reason": "source_unresolved", "requirements": [], "world_provider_paths": [], "wallet_zenny": _inventory.get_zenny() if _inventory != null else 0})
	var catalog = _shops if row.source_type == "shop_offer" else _trades
	if catalog == null:
		return row
	var source = catalog.get_offer_by_id(StringName(row.source_id)) if row.source_type == "shop_offer" else catalog.get_recipe_by_id(StringName(row.source_id))
	if source == null or not source.is_valid_definition():
		return row
	# Detect stale plan links instead of describing a different authored reward.
	var reward_id: StringName = source.item_id if row.source_type == "shop_offer" else source.reward_id
	var reward_type: int = source.item_type if row.source_type == "shop_offer" else source.reward_type
	if reward_id != id or reward_type != (1 if row.kind == "rod" else 0):
		row.reason = "source_reward_mismatch"
		return row
	row.source_exists = true
	row.shop_id = String(source.shop_id)
	row.reason = "world_context_unavailable"
	for provider: Dictionary in sources:
		var context = provider.get("context")
		if not (context is ContextScript) or context.full_catalog_access:
			continue # Explicit debug access is never world progression evidence.
		var allowed: PackedStringArray = context.shop_ids if row.source_type == "shop_offer" else context.trade_shop_ids
		if not allowed.has(row.shop_id):
			continue
		if row.source_type == "shop_offer" and source.availability_tag != &"" and not bool(context.availability.get(source.availability_tag, context.availability.get(String(source.availability_tag), false))):
			if not row.accessible:
				row.reason = "availability_locked"
			continue
		row.accessible = true
		row.reason = "ok"
		row.world_provider_paths.append(str(provider.get("path", "")))
	if row.source_type == "shop_offer":
		var status := _economy.evaluate_purchase(source) if _economy != null else {}
		row.price_zenny = int(status.get("unit_price_zenny", 0))
		row.price_resolved = not status.is_empty() and status.get("reason", "") not in ["economy_unavailable", "invalid_offer"]
		row.requirements_met = row.price_resolved and row.wallet_zenny >= row.price_zenny
		if row.price_resolved:
			row.hint = "Save for / buy %s from the %s (%dz; have %dz)." % [row.target, row.source_label, row.price_zenny, row.wallet_zenny]
		else:
			row.hint = "Buy %s from the %s (live price unavailable)." % [row.target, row.source_label]
	else:
		row.requirements_met = true
		var parts := PackedStringArray()
		var costs: Dictionary = source.get_cost_dictionary()
		for fish_id: String in costs:
			var required: int = costs[fish_id]
			var count := _inventory.get_fish_count(fish_id) if _inventory != null else 0
			var fish = _content.get_fish_by_id(StringName(fish_id)) if _content != null else null
			var name: String = fish.fish_name if fish != null else fish_id
			var authored_spots := PackedStringArray()
			for spot in (_content.spots if _content != null else []):
				if _spot_has_species(spot, fish_id):
					authored_spots.append(String(spot.spot_id))
			var available := false
			for spot in spots:
				available = available or _spot_has_species(spot, fish_id)
			row.requirements.append({"species_id": fish_id, "name": name, "owned": count, "required": required, "missing": maxi(0, required - count), "available_in_current_spots": available, "authored_spot_ids": authored_spots})
			row.requirements_met = row.requirements_met and count >= required
			parts.append("%s %d/%d" % [name, count, required])
		row.hint = "%s: trade at %s — %s." % [row.target, row.source_label, "; ".join(parts)]
	if not row.accessible:
		row.hint += " Source unavailable in the current world."
	return row

func _spot_has_species(spot, species_id: String) -> bool:
	if spot == null:
		return false
	for entry in spot.fish_population:
		if entry != null and entry.fish != null and entry.get_base_bite_weight() > 0 and entry.fish.get_stable_species_id() == species_id:
			return true
	return false
