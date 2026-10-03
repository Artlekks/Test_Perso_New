extends RefCounted
class_name FishingEconomyIntegrity

const ShopOfferScript = preload("res://scripts/database/fishing_shop_offer.gd")


static func audit(
	content_catalog: FishingContentCatalog,
	shop_catalog,
	trade_catalog: FishingTradeCatalog,
	economy_config: FishingEconomyConfig = null
) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var seen_offers: Dictionary = {}
	var seen_recipes: Dictionary = {}
	var fish_ids: Dictionary = {}

	if content_catalog == null:
		errors.append("content catalog missing")
		return {"ok": false, "errors": errors, "warnings": warnings}
	if content_catalog.tackle == null:
		errors.append("tackle catalog missing")

	if economy_config == null:
		warnings.append("canonical fishing economy config missing; legacy prices are active")
	else:
		var config_shape: Dictionary = economy_config.validate_shape()
		for error in config_shape.get("errors", PackedStringArray()):
			errors.append("economy config: %s" % str(error))

	for fish in content_catalog.fish:
		if fish == null:
			errors.append("null fish entry")
			continue
		var species_id: String = str(fish.get_stable_species_id()).strip_edges().to_lower()
		fish_ids[species_id] = true
		var live_sell_value: int = fish.get_sell_value_zenny()
		if economy_config != null:
			live_sell_value = economy_config.get_fish_sell_price(
				StringName(species_id),
				0
			)
		if live_sell_value <= 0:
			errors.append("%s has no canonical sell value" % fish.fish_name)
		if fish.get_legacy_item_effect().strip_edges().is_empty():
			warnings.append("%s has no BOF4 item-effect reference" % fish.fish_name)

	if shop_catalog == null:
		errors.append("shop catalog missing")
	else:
		for offer in shop_catalog.get_all_offers():
			var offer_id := str(offer.offer_id)
			if seen_offers.has(offer_id):
				errors.append("duplicate shop offer %s" % offer_id)
			seen_offers[offer_id] = true
			if offer.price_zenny < 0:
				errors.append("%s has negative legacy price" % offer_id)
			if (
				economy_config != null
				and economy_config.get_offer_buy_price(
					int(offer.item_type),
					offer.item_id,
					0
				) <= 0
			):
				errors.append("%s has no canonical economy price" % offer_id)
			if content_catalog.tackle != null:
				match offer.item_type:
					ShopOfferScript.ItemType.LURE:
						if not content_catalog.tackle.has_lure(offer.item_id):
							errors.append("%s references unknown lure %s" % [offer_id, offer.item_id])
					ShopOfferScript.ItemType.ROD:
						if not content_catalog.tackle.has_rod(offer.item_id):
							errors.append("%s references unknown rod %s" % [offer_id, offer.item_id])

	if trade_catalog == null:
		errors.append("trade catalog missing")
	else:
		for recipe in trade_catalog.get_all_recipes():
			var recipe_id := str(recipe.recipe_id)
			if seen_recipes.has(recipe_id):
				errors.append("duplicate trade recipe %s" % recipe_id)
			seen_recipes[recipe_id] = true
			for fish_id in recipe.required_fish_ids:
				if not fish_ids.has(str(fish_id).to_lower()):
					errors.append("%s references unknown fish %s" % [recipe_id, fish_id])

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"fish_count": fish_ids.size(),
		"shop_offer_count": seen_offers.size(),
		"trade_recipe_count": seen_recipes.size(),
	}
