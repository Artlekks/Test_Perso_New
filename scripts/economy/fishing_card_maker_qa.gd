extends RefCounted
class_name FishingCardMakerQA

const WORLD_MAP_PATH := "res://data/triple_triad/acquisition/world_acquisition_map.json"


static func run(
	catalog: FishingCardMakerCatalog,
	content_catalog: Resource,
	card_catalog: Resource
) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}
	var audit: Dictionary = (
		catalog.validate_catalog(content_catalog, card_catalog)
		if catalog != null
		else {"valid": false, "recipe_count": 0}
	)
	_record(
		report,
		"Card-maker catalog validates",
		bool(audit.get("valid", false)),
		"Recipe ids, fish ids and card ids must all resolve."
	)
	_record(
		report,
		"Prototype catalog exposes five recipes",
		int(audit.get("recipe_count", 0)) == 5,
		"Foundation v1 intentionally starts with five early fish-to-card recipes."
	)

	var recipes: Array[FishingCardMakerRecipe] = (
		catalog.get_all_recipes()
		if catalog != null
		else []
	)
	var all_fish_valid: bool = not recipes.is_empty()
	var all_cards_valid: bool = not recipes.is_empty()
	for recipe in recipes:
		if (
			content_catalog == null
			or not content_catalog.has_method("get_fish_by_id")
			or content_catalog.call("get_fish_by_id", recipe.fish_species_id) == null
		):
			all_fish_valid = false
		if (
			card_catalog == null
			or not card_catalog.has_method("get_card_by_id")
			or card_catalog.call("get_card_by_id", recipe.card_id) == null
		):
			all_cards_valid = false
	_record(
		report,
		"All recipes reference real fish species",
		all_fish_valid,
		"Card Maker inputs must remain tied to canonical fishing content ids."
	)
	_record(
		report,
		"All recipes reference real cards",
		all_cards_valid,
		"Prototype outputs must resolve through the canonical Triple Triad catalog."
	)
	_record(
		report,
		"World acquisition map mirrors every Card Maker recipe",
		_world_source_contract_ok(recipes),
		"Card Maker rewards must appear in the same acquisition-source model as NPC, treasure and fishing rewards."
	)

	var quote_service := FishingCardMakerService.new()
	var sample: FishingCardMakerRecipe = (
		recipes[0]
		if not recipes.is_empty()
		else null
	)
	var first_quote: Dictionary = (
		quote_service.build_quote_from_state(sample, 1, 1000, 0, 1)
		if sample != null
		else {}
	)
	_record(
		report,
		"First creation consumes one fish plus the first-time fee",
		bool(first_quote.get("can_make", false))
		and int(first_quote.get("fish_required", 0)) == 1
		and int(first_quote.get("zenny_required", 0)) == 75,
		"The first card should create a real sell/use/card decision for the caught fish."
	)

	var duplicate_quote: Dictionary = (
		quote_service.build_quote_from_state(sample, 0, 1000, 1, 1)
		if sample != null
		else {}
	)
	_record(
		report,
		"Duplicate printing does not consume another specimen",
		bool(duplicate_quote.get("can_make", false))
		and int(duplicate_quote.get("fish_required", -1)) == 0
		and int(duplicate_quote.get("zenny_required", 0)) == 150,
		"After discovery, duplicate cards should be a money sink rather than permanent rare-fish hoarding pressure."
	)

	var missing_fish_quote: Dictionary = (
		quote_service.build_quote_from_state(sample, 0, 1000, 0, 1)
		if sample != null
		else {}
	)
	_record(
		report,
		"First creation rejects a missing fish",
		str(missing_fish_quote.get("reason", "")) == "not_enough_fish",
		"A fish-linked card cannot be first-created without the associated species."
	)

	var missing_zenny_quote: Dictionary = (
		quote_service.build_quote_from_state(sample, 1, 0, 0, 1)
		if sample != null
		else {}
	)
	_record(
		report,
		"Card Maker rejects an unaffordable fee",
		str(missing_zenny_quote.get("reason", "")) == "not_enough_zenny",
		"Card printing is also an economy sink."
	)

	quote_service.free()
	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	report["catalog_audit"] = audit
	return report


static func _world_source_contract_ok(
	recipes: Array[FishingCardMakerRecipe]
) -> bool:
	if not FileAccess.file_exists(WORLD_MAP_PATH):
		return false
	var file := FileAccess.open(WORLD_MAP_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return false
	var root: Dictionary = parsed
	var direct_types = root.get("source_types_direct_claim", [])
	if not (direct_types is Array) or not direct_types.has("card_maker"):
		return false
	var mapped: Dictionary = {}
	var sources = root.get("sources", [])
	if not (sources is Array):
		return false
	for raw_source in sources:
		if not (raw_source is Dictionary):
			continue
		var source: Dictionary = raw_source
		if str(source.get("source_type", "")) != "card_maker":
			continue
		var ids = source.get("card_ids", [])
		if not (ids is Array) or ids.size() != 1:
			return false
		mapped[str(source.get("source_id", ""))] = str(ids[0])
	for recipe in recipes:
		if str(mapped.get(String(recipe.recipe_id), "")) != String(recipe.card_id):
			return false
	return true


static func _record(
	report: Dictionary,
	name: String,
	passed: bool,
	detail: String
) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get(
		"failures",
		PackedStringArray()
	)
	failures.append("%s — %s" % [name, detail])
	report["failures"] = failures
