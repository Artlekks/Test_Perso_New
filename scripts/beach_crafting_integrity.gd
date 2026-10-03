extends RefCounted
class_name BeachCraftingIntegrity


static func audit(
	catalog: BeachCraftingCatalog,
	tackle_catalog: FishingTackleCatalog
) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()

	if catalog == null:
		errors.append("Beach crafting catalog is missing.")
		return _report(errors, warnings, 0, 0)

	if catalog.materials.size() != 6:
		warnings.append(
			"Vertical slice expects 6 materials; found %d."
			% catalog.materials.size()
		)
	if catalog.recipes.size() != 3:
		warnings.append(
			"Vertical slice expects 3 recipes; found %d."
			% catalog.recipes.size()
		)

	var material_ids: Dictionary = {}
	for material in catalog.materials:
		if material == null:
			errors.append("Material catalog contains a null entry.")
			continue
		var material_id: String = String(material.material_id).strip_edges()
		if material_id.is_empty():
			errors.append("Material has an empty id.")
		elif material_ids.has(material_id):
			errors.append("Duplicate material id '%s'." % material_id)
		else:
			material_ids[material_id] = true

	var recipe_ids: Dictionary = {}
	for recipe in catalog.recipes:
		if recipe == null:
			errors.append("Recipe catalog contains a null entry.")
			continue
		var recipe_id: String = String(recipe.recipe_id).strip_edges()
		if recipe_id.is_empty():
			errors.append("Recipe has an empty id.")
		elif recipe_ids.has(recipe_id):
			errors.append("Duplicate recipe id '%s'." % recipe_id)
		else:
			recipe_ids[recipe_id] = true

		if (
			tackle_catalog == null
			or tackle_catalog.get_lure_by_id(recipe.template_lure_id) == null
		):
			errors.append(
				"%s references missing lure template '%s'."
				% [recipe_id, String(recipe.template_lure_id)]
			)

		for field_entry in [
			{"name": "body", "ids": recipe.body_material_ids},
			{"name": "core", "ids": recipe.core_material_ids},
			{"name": "accent", "ids": recipe.accent_material_ids},
		]:
			var seen: Dictionary = {}
			for raw_id in field_entry["ids"]:
				var material_id: String = str(raw_id)
				if not material_ids.has(material_id):
					errors.append(
						"%s %s slot references unknown material '%s'."
						% [recipe_id, field_entry["name"], material_id]
					)
				if seen.has(material_id):
					errors.append(
						"%s %s slot repeats material '%s'."
						% [recipe_id, field_entry["name"], material_id]
					)
				seen[material_id] = true

		if recipe.body_material_ids.is_empty():
			errors.append("%s has no body materials." % recipe_id)
		if recipe.core_material_ids.is_empty():
			errors.append("%s has no core materials." % recipe_id)

	return _report(
		errors,
		warnings,
		catalog.materials.size(),
		catalog.recipes.size()
	)


static func _report(
	errors: PackedStringArray,
	warnings: PackedStringArray,
	material_count: int,
	recipe_count: int
) -> Dictionary:
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"material_count": material_count,
		"recipe_count": recipe_count,
	}
