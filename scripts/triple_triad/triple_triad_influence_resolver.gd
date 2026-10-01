extends RefCounted

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2
const GRID_WIDTH := 3
const GRID_HEIGHT := 3


func build_state(board: Array, enabled: bool = true) -> Dictionary:
	var player_pressure: Array[int] = []
	var opponent_pressure: Array[int] = []
	player_pressure.resize(board.size())
	opponent_pressure.resize(board.size())
	player_pressure.fill(0)
	opponent_pressure.fill(0)

	if not enabled:
		return {
			"player_pressure": player_pressure,
			"opponent_pressure": opponent_pressure,
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
		for target_cell in projected_cells(card, source_index, rotation, board.size()):
			if owner == OWNER_PLAYER:
				player_pressure[target_cell] = maxi(player_pressure[target_cell], strength)
			else:
				opponent_pressure[target_cell] = maxi(opponent_pressure[target_cell], strength)

	return {
		"player_pressure": player_pressure,
		"opponent_pressure": opponent_pressure,
	}


func modifier_for_cell(state: Dictionary, cell_index: int, target_owner: int) -> int:
	if target_owner not in [OWNER_PLAYER, OWNER_OPPONENT] or cell_index < 0:
		return 0
	var pressure_key: String = "opponent_pressure" if target_owner == OWNER_PLAYER else "player_pressure"
	var pressure = state.get(pressure_key, [])
	if typeof(pressure) != TYPE_ARRAY or cell_index >= pressure.size():
		return 0
	# Prototype rule: pressure does not stack. The strongest opposing source wins.
	return -maxi(0, int(pressure[cell_index]))


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
		offsets = card.call("get_influence_offsets_rotated", rotation_quarters)
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
		if column < 0 or column >= GRID_WIDTH or row < 0 or row >= GRID_HEIGHT:
			continue
		var target: int = row * GRID_WIDTH + column
		if target >= 0 and target < board_size and not result.has(target):
			result.append(target)
	return result


func _card_projects_pressure(card) -> bool:
	if card == null:
		return false
	if card.has_method("has_influence") and not bool(card.call("has_influence")):
		return false
	var mode = card.get("influence_mode")
	return mode != null and String(mode) == "pressure"
