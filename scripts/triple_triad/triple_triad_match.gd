extends RefCounted

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const SIDE_TOP := 0
const SIDE_RIGHT := 1
const SIDE_BOTTOM := 2
const SIDE_LEFT := 3

const DIRECTIONS := [
	{"offset": -3, "side": SIDE_TOP, "opposite": SIDE_BOTTOM},
	{"offset": 1, "side": SIDE_RIGHT, "opposite": SIDE_LEFT},
	{"offset": 3, "side": SIDE_BOTTOM, "opposite": SIDE_TOP},
	{"offset": -1, "side": SIDE_LEFT, "opposite": SIDE_RIGHT},
]

var board: Array = []
var player_hand: Array = []
var opponent_hand: Array = []
var player_hand_rotations: Array[int] = []
var opponent_hand_rotations: Array[int] = []
var player_rotate_used: bool = false
var opponent_rotate_used: bool = false
var current_owner: int = OWNER_PLAYER
var starting_owner: int = OWNER_PLAYER
var game_over: bool = false
var turn_number: int = 0
var rule_set: Resource = null
var region_profile: Resource = null


func reset_match(
	player_cards: Array,
	opponent_cards: Array,
	first_owner: int,
	rules: Resource = null,
	region: Resource = null
) -> void:
	board.clear()
	board.resize(9)
	for cell_index in range(9):
		board[cell_index] = null
	player_hand = player_cards.duplicate()
	opponent_hand = opponent_cards.duplicate()
	player_hand_rotations.clear()
	opponent_hand_rotations.clear()
	for _card in player_hand:
		player_hand_rotations.append(0)
	for _card in opponent_hand:
		opponent_hand_rotations.append(0)
	player_rotate_used = false
	opponent_rotate_used = false
	starting_owner = first_owner if first_owner in [OWNER_PLAYER, OWNER_OPPONENT] else OWNER_PLAYER
	current_owner = starting_owner
	game_over = false
	turn_number = 0
	rule_set = rules
	region_profile = region


func can_place(card_owner: int, hand_index: int, cell_index: int) -> bool:
	if game_over or card_owner != current_owner:
		return false
	if cell_index < 0 or cell_index >= board.size():
		return false
	if board[cell_index] != null:
		return false
	var hand: Array = _hand_for_owner(card_owner)
	return hand_index >= 0 and hand_index < hand.size()


func can_rotate(card_owner: int, hand_index: int = -1) -> bool:
	if game_over:
		return false
	if region_profile != null and region_profile.has_method("get"):
		var rotate_value = region_profile.get("allow_rotate")
		if rotate_value != null and not bool(rotate_value):
			return false
	if card_owner == OWNER_PLAYER and player_rotate_used:
		return false
	if card_owner == OWNER_OPPONENT and opponent_rotate_used:
		return false
	if hand_index >= 0:
		var hand: Array = _hand_for_owner(card_owner)
		if hand_index >= hand.size():
			return false
	return card_owner in [OWNER_PLAYER, OWNER_OPPONENT]


func rotate_hand_card(card_owner: int, hand_index: int) -> bool:
	if not can_rotate(card_owner, hand_index):
		return false
	var rotations: Array[int] = _hand_rotations_for_owner(card_owner)
	rotations[hand_index] = posmod(rotations[hand_index] + 1, 4)
	if card_owner == OWNER_PLAYER:
		player_rotate_used = true
	else:
		opponent_rotate_used = true
	return true


func get_hand_rotation(card_owner: int, hand_index: int) -> int:
	var rotations: Array[int] = _hand_rotations_for_owner(card_owner)
	if hand_index < 0 or hand_index >= rotations.size():
		return 0
	return rotations[hand_index]


func place_card(card_owner: int, hand_index: int, cell_index: int) -> Dictionary:
	if not can_place(card_owner, hand_index, cell_index):
		return {"success": false, "reason": "invalid_move"}

	var hand: Array = _hand_for_owner(card_owner)
	var rotations: Array[int] = _hand_rotations_for_owner(card_owner)
	var card = hand[hand_index]
	var card_rotation: int = rotations[hand_index]
	hand.remove_at(hand_index)
	rotations.remove_at(hand_index)
	board[cell_index] = {
		"card": card,
		"owner": card_owner,
		"rotation": card_rotation,
	}

	var capture_result: Dictionary = _resolve_captures(cell_index, card_owner)
	turn_number += 1
	game_over = _occupied_count() >= 9
	if not game_over:
		current_owner = _other_owner(card_owner)

	return {
		"success": true,
		"cell_index": cell_index,
		"owner": card_owner,
		"rotation": card_rotation,
		"captured": capture_result["captured"],
		"basic_captured": capture_result["basic_captured"],
		"same_captured": capture_result["same_captured"],
		"combo_captured": capture_result["combo_captured"],
		"same_match_count": capture_result["same_match_count"],
		"same_triggered": capture_result["same_triggered"],
		"game_over": game_over,
		"score": get_score(),
		"winner": get_winner(),
	}


func preview_move(card, card_owner: int, cell_index: int, rotation_quarters: int = 0) -> Dictionary:
	if card == null or cell_index < 0 or cell_index >= board.size() or board[cell_index] != null:
		return {
			"valid": false,
			"captured": [],
			"capture_count": -1,
			"same_triggered": false,
			"same_match_count": 0,
		}

	var original_board: Array = board
	board = board.duplicate(true)
	board[cell_index] = {
		"card": card,
		"owner": card_owner,
		"rotation": posmod(rotation_quarters, 4),
	}
	var capture_result: Dictionary = _resolve_captures(cell_index, card_owner)
	board = original_board
	return {
		"valid": true,
		"captured": capture_result["captured"],
		"capture_count": (capture_result["captured"] as Array).size(),
		"basic_captured": capture_result["basic_captured"],
		"same_captured": capture_result["same_captured"],
		"combo_captured": capture_result["combo_captured"],
		"same_triggered": capture_result["same_triggered"],
		"same_match_count": capture_result["same_match_count"],
	}


func preview_capture_count(card, card_owner: int, cell_index: int, rotation_quarters: int = 0) -> int:
	var preview: Dictionary = preview_move(card, card_owner, cell_index, rotation_quarters)
	return int(preview.get("capture_count", -1))


func effective_rank_for_card(card, side: int, rotation_quarters: int = 0, cell_index: int = -1) -> int:
	if card == null:
		return 0
	var base_rank: int
	if card.has_method("rank_for_side_rotated"):
		base_rank = int(card.rank_for_side_rotated(side, rotation_quarters))
	else:
		base_rank = int(card.rank_for_side(side))
	return clampi(base_rank + get_cell_rank_bonus(cell_index), 1, 10)


func get_cell_rank_bonus(cell_index: int) -> int:
	if region_profile == null or cell_index < 0 or cell_index >= 9:
		return 0
	if region_profile.has_method("rank_bonus_for_cell"):
		return int(region_profile.call("rank_bonus_for_cell", cell_index))
	return 0


func get_empty_cells() -> Array[int]:
	var result: Array[int] = []
	for cell_index in range(board.size()):
		if board[cell_index] == null:
			result.append(cell_index)
	return result


func get_hand(card_owner: int) -> Array:
	return _hand_for_owner(card_owner)


func get_score() -> Dictionary:
	var player_score: int = player_hand.size()
	var opponent_score: int = opponent_hand.size()
	for slot_variant in board:
		if slot_variant == null:
			continue
		var slot: Dictionary = slot_variant
		if int(slot["owner"]) == OWNER_PLAYER:
			player_score += 1
		elif int(slot["owner"]) == OWNER_OPPONENT:
			opponent_score += 1
	return {
		"player": player_score,
		"opponent": opponent_score,
	}


func get_winner() -> int:
	if not game_over:
		return OWNER_NONE
	var score: Dictionary = get_score()
	var player_score: int = int(score["player"])
	var opponent_score: int = int(score["opponent"])
	if player_score > opponent_score:
		return OWNER_PLAYER
	if opponent_score > player_score:
		return OWNER_OPPONENT
	return OWNER_NONE


func validate_state() -> bool:
	if board.size() != 9:
		return false
	if player_hand.size() + opponent_hand.size() + _occupied_count() != 10:
		return false
	if player_hand_rotations.size() != player_hand.size():
		return false
	if opponent_hand_rotations.size() != opponent_hand.size():
		return false
	for slot_variant in board:
		if slot_variant == null:
			continue
		var slot: Dictionary = slot_variant
		if not slot.has("card") or not slot.has("owner") or not slot.has("rotation"):
			return false
		if int(slot["owner"]) not in [OWNER_PLAYER, OWNER_OPPONENT]:
			return false
	return true


func _resolve_captures(cell_index: int, card_owner: int) -> Dictionary:
	var same_result: Dictionary = _resolve_same_captures(cell_index, card_owner)
	var same_captured: Array[int] = []
	same_captured.assign(same_result.get("captured", []))
	var basic_captured: Array[int] = _resolve_basic_captures(cell_index, card_owner)
	var combo_captured: Array[int] = []
	if _rule_enabled("combo_rule") and not same_captured.is_empty():
		combo_captured = _resolve_combo_captures(same_captured, card_owner)

	var captured: Array[int] = []
	_append_unique_cells(captured, same_captured)
	_append_unique_cells(captured, basic_captured)
	_append_unique_cells(captured, combo_captured)
	return {
		"captured": captured,
		"basic_captured": basic_captured,
		"same_captured": same_captured,
		"combo_captured": combo_captured,
		"same_match_count": int(same_result["match_count"]),
		"same_triggered": bool(same_result["triggered"]),
	}


func _resolve_same_captures(cell_index: int, card_owner: int) -> Dictionary:
	if not _rule_enabled("same_rule"):
		return {"captured": [], "match_count": 0, "triggered": false}

	var matching_neighbors: Array[int] = []
	var placed_slot: Dictionary = board[cell_index]
	for direction_variant in DIRECTIONS:
		var direction: Dictionary = direction_variant
		var side: int = int(direction["side"])
		var neighbor_index: int = cell_index + int(direction["offset"])
		if not _is_valid_neighbor(cell_index, neighbor_index, side):
			continue
		var neighbor_variant = board[neighbor_index]
		if neighbor_variant == null:
			continue
		var neighbor: Dictionary = neighbor_variant
		if _slot_rank(placed_slot, side, cell_index) == _slot_rank(neighbor, int(direction["opposite"]), neighbor_index):
			matching_neighbors.append(neighbor_index)

	if matching_neighbors.size() < 2:
		return {"captured": [], "match_count": matching_neighbors.size(), "triggered": false}

	var captured: Array[int] = []
	for neighbor_index in matching_neighbors:
		var neighbor: Dictionary = board[neighbor_index]
		if int(neighbor["owner"]) == card_owner:
			continue
		neighbor["owner"] = card_owner
		board[neighbor_index] = neighbor
		captured.append(neighbor_index)
	return {"captured": captured, "match_count": matching_neighbors.size(), "triggered": true}


func _resolve_basic_captures(cell_index: int, card_owner: int) -> Array[int]:
	var captured: Array[int] = []
	var placed_slot: Dictionary = board[cell_index]
	for direction_variant in DIRECTIONS:
		var direction: Dictionary = direction_variant
		var side: int = int(direction["side"])
		var neighbor_index: int = cell_index + int(direction["offset"])
		if not _is_valid_neighbor(cell_index, neighbor_index, side):
			continue
		var neighbor_variant = board[neighbor_index]
		if neighbor_variant == null:
			continue
		var neighbor: Dictionary = neighbor_variant
		if int(neighbor["owner"]) == card_owner:
			continue
		if _slot_rank(placed_slot, side, cell_index) > _slot_rank(neighbor, int(direction["opposite"]), neighbor_index):
			neighbor["owner"] = card_owner
			board[neighbor_index] = neighbor
			captured.append(neighbor_index)
	return captured


func _resolve_combo_captures(seed_cells: Array[int], card_owner: int) -> Array[int]:
	var captured: Array[int] = []
	var queue: Array[int] = seed_cells.duplicate()
	var cursor: int = 0
	while cursor < queue.size():
		var source_index: int = queue[cursor]
		cursor += 1
		var source_variant = board[source_index]
		if source_variant == null:
			continue
		var source_slot: Dictionary = source_variant
		for direction_variant in DIRECTIONS:
			var direction: Dictionary = direction_variant
			var side: int = int(direction["side"])
			var neighbor_index: int = source_index + int(direction["offset"])
			if not _is_valid_neighbor(source_index, neighbor_index, side):
				continue
			var neighbor_variant = board[neighbor_index]
			if neighbor_variant == null:
				continue
			var neighbor: Dictionary = neighbor_variant
			if int(neighbor["owner"]) == card_owner:
				continue
			if _slot_rank(source_slot, side, source_index) > _slot_rank(neighbor, int(direction["opposite"]), neighbor_index):
				neighbor["owner"] = card_owner
				board[neighbor_index] = neighbor
				captured.append(neighbor_index)
				queue.append(neighbor_index)
	return captured


func _slot_rank(slot: Dictionary, side: int, cell_index: int) -> int:
	var card = slot["card"]
	var rotation: int = int(slot.get("rotation", 0))
	return effective_rank_for_card(card, side, rotation, cell_index)


func _rule_enabled(property_name: StringName) -> bool:
	if rule_set == null:
		return false
	var value = rule_set.get(property_name)
	return value != null and bool(value)


func _append_unique_cells(target: Array[int], source: Array[int]) -> void:
	for cell_index in source:
		if not target.has(cell_index):
			target.append(cell_index)


func _is_valid_neighbor(cell_index: int, neighbor_index: int, side: int) -> bool:
	if neighbor_index < 0 or neighbor_index >= board.size():
		return false
	var row: int = floori(float(cell_index) / 3.0)
	var column: int = cell_index % 3
	match side:
		SIDE_TOP:
			return row > 0
		SIDE_RIGHT:
			return column < 2
		SIDE_BOTTOM:
			return row < 2
		SIDE_LEFT:
			return column > 0
		_:
			return false


func _hand_for_owner(card_owner: int) -> Array:
	return player_hand if card_owner == OWNER_PLAYER else opponent_hand


func _hand_rotations_for_owner(card_owner: int) -> Array[int]:
	return player_hand_rotations if card_owner == OWNER_PLAYER else opponent_hand_rotations


func _other_owner(card_owner: int) -> int:
	return OWNER_OPPONENT if card_owner == OWNER_PLAYER else OWNER_PLAYER


func _occupied_count() -> int:
	var count: int = 0
	for slot_variant in board:
		if slot_variant != null:
			count += 1
	return count
