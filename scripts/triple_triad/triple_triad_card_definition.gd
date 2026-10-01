extends Resource

@export var card_id: StringName = &""
@export var display_name: String = "Card"
@export_range(1, 10, 1) var level: int = 1
@export_range(1, 10, 1) var deck_cost: int = 1
@export_range(1, 10, 1) var top_rank: int = 1
@export_range(1, 10, 1) var right_rank: int = 1
@export_range(1, 10, 1) var bottom_rank: int = 1
@export_range(1, 10, 1) var left_rank: int = 1
@export var portrait: Texture2D
@export var source_index: int = -1
@export var source_kind: StringName = &"portrait"
@export var group_id: StringName = &""
@export var tags: PackedStringArray = PackedStringArray()
@export var rarity_id: StringName = &"standard"
@export_range(1, 10, 1) var required_player_rank: int = 1
@export var acquisition_tags: PackedStringArray = PackedStringArray()
@export var influence_mode: StringName = &"none"
@export_range(0, 2, 1) var influence_strength: int = 0
@export var influence_offsets: Array[Vector2i] = []


func has_influence() -> bool:
	return (
		String(influence_mode) == "pressure"
		and influence_strength > 0
		and not influence_offsets.is_empty()
	)


func get_influence_offsets_rotated(quarter_turns_clockwise: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var turns: int = posmod(quarter_turns_clockwise, 4)
	for authored_offset in influence_offsets:
		var offset: Vector2i = authored_offset
		for _turn in range(turns):
			offset = Vector2i(-offset.y, offset.x)
		result.append(offset)
	return result


func get_influence_display_name() -> String:
	match String(influence_mode):
		"pressure":
			return "Pressure"
		_:
			return "None"


func get_influence_description() -> String:
	if not has_influence():
		return "This card does not project Influence."
	match String(influence_mode):
		"pressure":
			return (
				"Projects -%d Pressure onto highlighted cells. "
				+ "Enemy cards there use reduced effective values."
			) % influence_strength
		_:
			return ""


func get_influence_grid_snapshot(quarter_turns_clockwise: int = 0) -> Dictionary:
	var offsets: Array[Vector2i] = get_influence_offsets_rotated(quarter_turns_clockwise)
	var min_x: int = 0
	var max_x: int = 0
	var min_y: int = 0
	var max_y: int = 0
	for offset in offsets:
		min_x = mini(min_x, offset.x)
		max_x = maxi(max_x, offset.x)
		min_y = mini(min_y, offset.y)
		max_y = maxi(max_y, offset.y)

	var width: int = max_x - min_x + 1
	var height: int = max_y - min_y + 1
	var rows: Array = []
	for _row in range(height):
		var row: Array[int] = []
		row.resize(width)
		row.fill(0)
		rows.append(row)

	var origin := Vector2i(-min_x, -min_y)
	if height > 0 and width > 0:
		var source_row: Array = rows[origin.y]
		source_row[origin.x] = 2
		rows[origin.y] = source_row
	for offset in offsets:
		var grid_position := Vector2i(offset.x - min_x, offset.y - min_y)
		if grid_position == origin:
			continue
		var target_row: Array = rows[grid_position.y]
		target_row[grid_position.x] = 1
		rows[grid_position.y] = target_row

	return {
		"width": width,
		"height": height,
		"origin": [origin.x, origin.y],
		"cells": rows,
	}


func get_influence_snapshot(quarter_turns_clockwise: int = 0) -> Dictionary:
	var rotated_offsets: Array[Vector2i] = get_influence_offsets_rotated(
		quarter_turns_clockwise
	)
	var serialized_offsets: Array = []
	for offset in rotated_offsets:
		serialized_offsets.append([offset.x, offset.y])
	return {
		"mode": String(influence_mode),
		"strength": influence_strength,
		"display_name": get_influence_display_name(),
		"description": get_influence_description(),
		"rotation_quarters": posmod(quarter_turns_clockwise, 4),
		"offsets": serialized_offsets,
		"grid": get_influence_grid_snapshot(quarter_turns_clockwise),
	}


func strength_points() -> int:
	# Deck points are currently the authoritative strength/economy value.
	# Keeping this method on the definition means UI/AI code does not need to know
	# where that value came from.
	return deck_cost


func is_usable_at_player_rank(player_rank: int) -> bool:
	return maxi(1, player_rank) >= required_player_rank


func has_acquisition_tag(tag: StringName) -> bool:
	var wanted: String = String(tag).strip_edges().to_lower()
	if wanted.is_empty():
		return false
	for raw_tag in acquisition_tags:
		if str(raw_tag).strip_edges().to_lower() == wanted:
			return true
	return false


func rank_for_side(side: int) -> int:
	match side:
		0:
			return top_rank
		1:
			return right_rank
		2:
			return bottom_rank
		3:
			return left_rank
		_:
			return 0


func rank_for_side_rotated(side: int, quarter_turns_clockwise: int) -> int:
	# Rotating the card clockwise moves its original top value to the right,
	# so the value currently facing a side comes from side - rotation.
	var source_side: int = posmod(side - posmod(quarter_turns_clockwise, 4), 4)
	return rank_for_side(source_side)


func rank_total() -> int:
	return top_rank + right_rank + bottom_rank + left_rank


func is_valid_definition() -> bool:
	return (
		not String(card_id).is_empty()
		and not String(source_kind).is_empty()
		and level >= 1
		and level <= 10
		and deck_cost >= 1
		and deck_cost <= 10
		and top_rank >= 1
		and top_rank <= 10
		and right_rank >= 1
		and right_rank <= 10
		and bottom_rank >= 1
		and bottom_rank <= 10
		and left_rank >= 1
		and left_rank <= 10
		and required_player_rank >= 1
		and required_player_rank <= 10
		and not String(rarity_id).strip_edges().is_empty()
		and influence_mode in [&"none", &"pressure"]
		and influence_strength >= 0
		and influence_strength <= 2
		and portrait != null
	)
