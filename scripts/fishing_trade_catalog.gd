extends Resource
class_name FishingTradeCatalog

@export var recipes: Array[FishingTradeRecipe] = []


func get_all_recipes() -> Array[FishingTradeRecipe]:
	var result: Array[FishingTradeRecipe] = []
	for recipe in recipes:
		if recipe != null:
			result.append(recipe)
	return result


func get_recipes_for_shop(shop_name: String) -> Array[FishingTradeRecipe]:
	var result: Array[FishingTradeRecipe] = []
	for recipe in recipes:
		if recipe != null and recipe.shop_name == shop_name:
			result.append(recipe)
	return result
