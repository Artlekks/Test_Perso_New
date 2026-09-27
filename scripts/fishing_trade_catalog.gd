extends Resource
class_name FishingTradeCatalog

@export var recipes: Array[FishingTradeRecipe] = []


func get_all_recipes() -> Array[FishingTradeRecipe]:
	var result: Array[FishingTradeRecipe] = []

	for recipe in recipes:
		if (
			recipe != null
			and recipe.is_valid_definition()
		):
			result.append(recipe)

	result.sort_custom(
		Callable(self, "_recipe_less")
	)
	return result


func get_recipe_by_id(
	recipe_id: StringName
) -> FishingTradeRecipe:
	if recipe_id == &"":
		return null

	for recipe in recipes:
		if (
			recipe != null
			and recipe.recipe_id == recipe_id
		):
			return recipe

	return null


func get_recipes_for_shop_id(
	shop_id: StringName
) -> Array[FishingTradeRecipe]:
	var result: Array[FishingTradeRecipe] = []

	for recipe in get_all_recipes():
		if recipe.shop_id == shop_id:
			result.append(recipe)

	return result


func get_recipes_for_shop(
	shop_name: String
) -> Array[FishingTradeRecipe]:
	# Compatibility path for old callers. Runtime code should prefer stable
	# shop_id values instead of display strings.
	var normalized: String = (
		shop_name.strip_edges().to_lower()
	)

	var result: Array[FishingTradeRecipe] = []

	for recipe in get_all_recipes():
		if (
			recipe.shop_name.strip_edges().to_lower()
			== normalized
		):
			result.append(recipe)

	return result


func get_shop_ids() -> PackedStringArray:
	var seen: Dictionary = {}
	var result := PackedStringArray()

	for recipe in get_all_recipes():
		var key: String = str(recipe.shop_id)

		if seen.has(key):
			continue

		seen[key] = true
		result.append(key)

	return result


func get_shop_display_name(
	shop_id: StringName
) -> String:
	for recipe in get_all_recipes():
		if recipe.shop_id == shop_id:
			return recipe.shop_name

	return ""


func get_recipe_count_for_shop(
	shop_id: StringName
) -> int:
	return get_recipes_for_shop_id(
		shop_id
	).size()


func get_debug_summary() -> String:
	var shop_ids: PackedStringArray = get_shop_ids()
	return "%d shops / %d recipes" % [
		shop_ids.size(),
		get_all_recipes().size(),
	]


func _recipe_less(
	a: FishingTradeRecipe,
	b: FishingTradeRecipe
) -> bool:
	var shop_compare: int = (
		str(a.shop_id).naturalnocasecmp_to(
			str(b.shop_id)
		)
	)

	if shop_compare != 0:
		return shop_compare < 0

	if a.sort_order != b.sort_order:
		return a.sort_order < b.sort_order

	return (
		str(a.recipe_id).naturalnocasecmp_to(
			str(b.recipe_id)
		)
		< 0
	)
