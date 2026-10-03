extends Resource
class_name FishingCardMakerRecipe

@export_category("Identity")
@export var recipe_id: StringName = &"card_recipe"
@export var display_name: String = "Card Recipe"
@export_multiline var description: String = ""
@export var enabled: bool = true

@export_category("Inputs")
@export var fish_species_id: StringName = &""
@export_range(0, 99, 1) var first_time_fish_count: int = 1
@export_range(0, 999999, 1) var first_time_zenny: int = 75
@export_range(0, 99, 1) var duplicate_fish_count: int = 0
@export_range(0, 999999, 1) var duplicate_zenny: int = 150

@export_category("Output")
@export var card_id: StringName = &""
@export_range(1, 10, 1) var minimum_duel_rank: int = 1


func validate_recipe(
	content_catalog: Resource = null,
	card_catalog: Resource = null
) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	if String(recipe_id).strip_edges().is_empty():
		errors.append("recipe_id is empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name is empty")
	if String(fish_species_id).strip_edges().is_empty():
		errors.append("fish_species_id is empty")
	if String(card_id).strip_edges().is_empty():
		errors.append("card_id is empty")
	if first_time_fish_count <= 0:
		warnings.append("first-time recipe consumes no fish")
	if duplicate_fish_count > first_time_fish_count:
		warnings.append("duplicate recipe consumes more fish than first creation")
	if duplicate_zenny < first_time_zenny:
		warnings.append("duplicate recipe is cheaper than first creation")

	if (
		content_catalog != null
		and content_catalog.has_method("get_fish_by_id")
		and content_catalog.call("get_fish_by_id", fish_species_id) == null
	):
		errors.append("unknown fish_species_id: %s" % String(fish_species_id))
	if (
		card_catalog != null
		and card_catalog.has_method("get_card_by_id")
		and card_catalog.call("get_card_by_id", card_id) == null
	):
		errors.append("unknown card_id: %s" % String(card_id))

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}
