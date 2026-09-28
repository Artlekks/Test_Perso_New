extends Resource

@export var region_id: StringName = &"default"
@export var display_name: String = "Default Region"
@export var board_trait_name: String = ""
@export_multiline var board_trait_description: String = ""
@export_range(5, 50, 1) var deck_budget: int = 30
@export var allow_rotate: bool = true
@export var rule_set: Resource
@export var cell_rank_bonuses: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])


func rank_bonus_for_cell(cell_index: int) -> int:
	if cell_index < 0 or cell_index >= cell_rank_bonuses.size():
		return 0
	return int(cell_rank_bonuses[cell_index])


func has_board_trait() -> bool:
	if not board_trait_name.strip_edges().is_empty():
		return true
	for value in cell_rank_bonuses:
		if int(value) != 0:
			return true
	return false


func validate_profile() -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	if String(region_id).is_empty():
		errors.append("region_id is empty")
	if cell_rank_bonuses.size() != 9:
		errors.append("cell_rank_bonuses must contain exactly 9 values")
	if deck_budget < 5:
		errors.append("deck_budget is too low")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
	}
