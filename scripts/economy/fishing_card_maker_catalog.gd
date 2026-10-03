extends Resource
class_name FishingCardMakerCatalog

@export var recipes: Array[FishingCardMakerRecipe] = []

var _cache: Dictionary = {}


func get_recipe(recipe_id: StringName) -> FishingCardMakerRecipe:
	_ensure_cache()
	return _cache.get(recipe_id, null)


func get_all_recipes() -> Array[FishingCardMakerRecipe]:
	var result: Array[FishingCardMakerRecipe] = []
	for recipe in recipes:
		if recipe != null and recipe.enabled:
			result.append(recipe)
	return result


func validate_catalog(
	content_catalog: Resource = null,
	card_catalog: Resource = null
) -> Dictionary:
	_cache.clear()
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var seen: Dictionary = {}
	var fish_to_card: Dictionary = {}

	for index in range(recipes.size()):
		var recipe: FishingCardMakerRecipe = recipes[index]
		if recipe == null:
			errors.append("null card-maker recipe at index %d" % index)
			continue
		var key: String = String(recipe.recipe_id).strip_edges()
		if key.is_empty():
			errors.append("empty card-maker recipe id at index %d" % index)
			continue
		if seen.has(key):
			errors.append("duplicate card-maker recipe id: %s" % key)
			continue
		seen[key] = true
		_cache[recipe.recipe_id] = recipe
		if not recipe.enabled:
			continue

		var audit: Dictionary = recipe.validate_recipe(
			content_catalog,
			card_catalog
		)
		for error_text in audit.get("errors", []):
			errors.append("%s: %s" % [key, str(error_text)])
		for warning_text in audit.get("warnings", []):
			warnings.append("%s: %s" % [key, str(warning_text)])

		var fish_key: String = String(recipe.fish_species_id)
		var card_key: String = String(recipe.card_id)
		if fish_to_card.has(fish_key) and str(fish_to_card[fish_key]) != card_key:
			warnings.append("fish %s has multiple prototype card outputs" % fish_key)
		fish_to_card[fish_key] = card_key

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"recipe_count": get_all_recipes().size(),
	}


func invalidate_cache() -> void:
	_cache.clear()


func _ensure_cache() -> void:
	if _cache.size() == recipes.size() and not recipes.is_empty():
		return
	_cache.clear()
	for recipe in recipes:
		if recipe == null:
			continue
		if String(recipe.recipe_id).strip_edges().is_empty():
			continue
		if not _cache.has(recipe.recipe_id):
			_cache[recipe.recipe_id] = recipe
