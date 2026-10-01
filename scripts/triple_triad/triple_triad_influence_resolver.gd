extends RefCounted

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2
const GRID_WIDTH := 3
const GRID_HEIGHT := 3


func build_state(board: Array, enabled: bool = true) -> Dictionary:
	var player_pressure: Array[int] = []
	var opponent_pressure: Array[int] = []
	var player_sources: Array = []
	var opponent_sources: Array = []
	player_pressure.resize(board.size())
	opponent_pressure.resize(board.size())
	player_pressure.fill(0)
	opponent_pressure.fill(0)
	for _index in range(board.size()):
		player_sources.append([])
		opponent_sources.append([])

	if not enabled:
		return {
			"player_pressure": player_pressure,
			"opponent_pressure": opponent_pressure,
			"player_sources": player_sources,
			"opponent_sources": opponent_sources,
		}

	for source_index in range(board.size()):
		var slot_variant = board[source_index]
		if slot_variant == null:
			continue
		var slot: Dictionary = slot_variant
		var owner: int = int(slot.get("owner", OWNER_NONE))
		if owner not in [OWNER_PLAYER, OWNER_OPPONENT]:
			continue
		var card = slot.get("card", null)
		if card == null or not _card_projects_pressure(card):
			continue
		var rotation: int = int(slot.get("rotation", 0))
		var strength: int = maxi(0, int(card.get("influence_strength")))
		if strength <= 0:
			continue

		var source_descriptor: Dictionary = {
			"source_cell": source_index,
			"source_owner": owner,
			"card_id": String(card.get("card_id")),
			"display_name": str(card.get("display_name")),
			"strength": strength,
			"rotation": rotation,
		}
		for target_cell in projected_cells(
			card,
			source_index,
			rotation,
			board.size()
		):
			if owner == OWNER_PLAYER:
				player_pressure[target_cell] = maxi(
					player_pressure[target_cell],
					strength
				)
				var sources: Array = player_sources[target_cell]
				sources.append(source_descriptor.duplicate(true))
				player_sources[target_cell] = sources
			else:
				opponent_pressure[target_cell] = maxi(
					opponent_pressure[target_cell],
					strength
				)
				var sources: Array = opponent_sources[target_cell]
				sources.append(source_descriptor.duplicate(true))
				opponent_sources[target_cell] = sources

	return {
		"player_pressure": player_pressure,
		"opponent_pressure": opponent_pressure,
		"player_sources": player_sources,
		"opponent_sources": opponent_sources,
	}


func modifier_for_cell(
	state: Dictionary,
	cell_index: int,
	target_owner: int
) -> int:
	if target_owner not in [OWNER_PLAYER, OWNER_OPPONENT] or cell_index < 0:
		return 0
	var pressure_key: String = (
		"opponent_pressure"
		if target_owner == OWNER_PLAYER
		else "player_pressure"
	)
	var pressure = state.get(pressure_key, [])
	if typeof(pressure) != TYPE_ARRAY or cell_index >= pressure.size():
		return 0
	# Pressure does not stack. The strongest opposing source wins.
	return -maxi(0, int(pressure[cell_index]))


func get_sources_for_cell(
	state: Dictionary,
	cell_index: int,
	source_owner: int
) -> Array:
	if cell_index < 0 or source_owner not in [OWNER_PLAYER, OWNER_OPPONENT]:
		return []
	var key: String = (
		"player_sources"
		if source_owner == OWNER_PLAYER
		else "opponent_sources"
	)
	var source_grid = state.get(key, [])
	if typeof(source_grid) != TYPE_ARRAY or cell_index >= source_grid.size():
		return []
	var sources = source_grid[cell_index]
	return sources.duplicate(true) if sources is Array else []


func cell_snapshot(
	state: Dictionary,
	cell_index: int,
	target_owner: int = OWNER_NONE
) -> Dictionary:
	var player_pressure: Array = state.get("player_pressure", [])
	var opponent_pressure: Array = state.get("opponent_pressure", [])
	var player_value: int = (
		int(player_pressure[cell_index])
		if cell_index >= 0 and cell_index < player_pressure.size()
		else 0
	)
	var opponent_value: int = (
		int(opponent_pressure[cell_index])
		if cell_index >= 0 and cell_index < opponent_pressure.size()
		else 0
	)
	var opposing_owner: int = OWNER_NONE
	if target_owner == OWNER_PLAYER:
		opposing_owner = OWNER_OPPONENT
	elif target_owner == OWNER_OPPONENT:
		opposing_owner = OWNER_PLAYER
	return {
		"cell_index": cell_index,
		"player_pressure": player_value,
		"opponent_pressure": opponent_value,
		"target_owner": target_owner,
		"modifier": (
			modifier_for_cell(state, cell_index, target_owner)
			if target_owner in [OWNER_PLAYER, OWNER_OPPONENT]
			else 0
		),
		"player_sources": get_sources_for_cell(
			state,
			cell_index,
			OWNER_PLAYER
		),
		"opponent_sources": get_sources_for_cell(
			state,
			cell_index,
			OWNER_OPPONENT
		),
		"opposing_sources": (
			get_sources_for_cell(state, cell_index, opposing_owner)
			if opposing_owner != OWNER_NONE
			else []
		),
	}


func projected_cells(
	card,
	source_index: int,
	rotation_quarters: int = 0,
	board_size: int = GRID_WIDTH * GRID_HEIGHT
) -> Array[int]:
	var result: Array[int] = []
	if card == null or source_index < 0 or source_index >= board_size:
		return result
	if not _card_projects_pressure(card):
		return result

	var offsets: Array = []
	if card.has_method("get_influence_offsets_rotated"):
		offsets = card.call(
			"get_influence_offsets_rotated",
			rotation_quarters
		)
	else:
		var raw_offsets = card.get("influence_offsets")
		if typeof(raw_offsets) == TYPE_ARRAY:
			offsets = raw_offsets

	var source_row: int = floori(float(source_index) / float(GRID_WIDTH))
	var source_column: int = source_index % GRID_WIDTH
	for raw_offset in offsets:
		var offset: Vector2i
		if typeof(raw_offset) == TYPE_VECTOR2I:
			offset = raw_offset
		elif typeof(raw_offset) == TYPE_VECTOR2:
			offset = Vector2i(int(raw_offset.x), int(raw_offset.y))
		else:
			continue
		var column: int = source_column + offset.x
		var row: int = source_row + offset.y
		if (
			column < 0
			or column >= GRID_WIDTH
			or row < 0
			or row >= GRID_HEIGHT
		):
			continue
		var target: int = row * GRID_WIDTH + column
		if (
			target >= 0
			and target < board_size
			and not result.has(target)
		):
			result.append(target)
	return result


func _card_projects_pressure(card) -> bool:
	if card == null:
		return false
	if card.has_method("has_influence") and not bool(card.call("has_influence")):
		return false
	var mode = card.get("influence_mode")
	return mode != null and String(mode) == "pressure"
