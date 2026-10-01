extends Resource
class_name BeachCraftingCatalog

@export var materials: Array[BeachMaterialDefinition] = []
@export var recipes: Array[BeachCraftingRecipe] = []


func get_material(material_id: StringName) -> BeachMaterialDefinition:
	for material in materials:
		if material != null and material.material_id == material_id:
			return material
	return null


func get_recipe(recipe_id: StringName) -> BeachCraftingRecipe:
	for recipe in recipes:
		if recipe != null and recipe.recipe_id == recipe_id:
			return recipe
	return null


func get_material_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for material in materials:
		if material != null and material.material_id != &"":
			result.append(String(material.material_id))
	return result


func get_recipe_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for recipe in recipes:
		if recipe != null and recipe.recipe_id != &"":
			result.append(String(recipe.recipe_id))
	return result
