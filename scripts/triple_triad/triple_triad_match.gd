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
var current_owner: int = OWNER_PLAYER
var starting_owner: int = OWNER_PLAYER
var game_over: bool = false
var turn_number: int = 0
var rule_set: Resource = null


func reset_match(player_cards: Array, opponent_cards: Array, first_owner: int, rules: Resource = null) -> void:
	board.clear()
	board.resize(9)
	for cell_index in range(9):
		board[cell_index] = null
	player_hand = player_cards.duplicate()
	opponent_hand = opponent_cards.duplicate()
	starting_owner = first_owner if first_owner in [OWNER_PLAYER, OWNER_OPPONENT] else OWNER_PLAYER
	current_owner = starting_owner
	game_over = false
	turn_number = 0
	rule_set = rules


func can_place(owner: int, hand_index: int, cell_index: int) -> bool:
	if game_over or owner != current_owner:
		return false
	if cell_index < 0 or cell_index >= board.size():
		return false
	if board[cell_index] != null:
		return false
	var hand: Array = _hand_for_owner(owner)
	return hand_index >= 0 and hand_index < hand.size()


func place_card(owner: int, hand_index: int, cell_index: int) -> Dictionary:
	if not can_place(owner, hand_index, cell_index):
		return {"success": false, "reason": "invalid_move"}

	var hand: Array = _hand_for_owner(owner)
	var card = hand[hand_index]
	hand.remove_at(hand_index)
	board[cell_index] = {
		"card": card,
		"owner": owner,
	}

	var captured: Array[int] = _resolve_basic_captures(cell_index, owner)
	turn_number += 1
	game_over = _occupied_count() >= 9
	if not game_over:
		current_owner = _other_owner(owner)

	return {
		"success": true,
		"cell_index": cell_index,
		"owner": owner,
		"captured": captured,
		"game_over": game_over,
		"score": get_score(),
		"winner": get_winner(),
	}


func preview_capture_count(card, owner: int, cell_index: int) -> int:
	if card == null or cell_index < 0 or cell_index >= board.size() or board[cell_index] != null:
		return -1
	var capture_count: int = 0
	for direction_variant in DIRECTIONS:
		var direction: Dictionary = direction_variant
		var neighbor_index: int = cell_index + int(direction["offset"])
		if not _is_valid_neighbor(cell_index, neighbor_index, int(direction["side"])):
			continue
		var neighbor = board[neighbor_index]
		if neighbor == null or int(neighbor["owner"]) == owner:
			continue
		var neighbor_card = neighbor["card"]
		if card.rank_for_side(int(direction["side"])) > neighbor_card.rank_for_side(int(direction["opposite"])):
			capture_count += 1
	return capture_count


func get_empty_cells() -> Array[int]:
	var result: Array[int] = []
	for cell_index in range(board.size()):
		if board[cell_index] == null:
			result.append(cell_index)
	return result


func get_hand(owner: int) -> Array:
	return _hand_for_owner(owner)


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
	for slot_variant in board:
		if slot_variant == null:
			continue
		var slot: Dictionary = slot_variant
		if not slot.has("card") or not slot.has("owner"):
			return false
		if int(slot["owner"]) not in [OWNER_PLAYER, OWNER_OPPONENT]:
			return false
	return true


func _resolve_basic_captures(cell_index: int, owner: int) -> Array[int]:
	var captured: Array[int] = []
	var placed_slot: Dictionary = board[cell_index]
	var placed_card = placed_slot["card"]
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
		if int(neighbor["owner"]) == owner:
			continue
		var neighbor_card = neighbor["card"]
		if placed_card.rank_for_side(side) > neighbor_card.rank_for_side(int(direction["opposite"])):
			neighbor["owner"] = owner
			board[neighbor_index] = neighbor
			captured.append(neighbor_index)
	return captured


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


func _hand_for_owner(owner: int) -> Array:
	return player_hand if owner == OWNER_PLAYER else opponent_hand


func _other_owner(owner: int) -> int:
	return OWNER_OPPONENT if owner == OWNER_PLAYER else OWNER_PLAYER


func _occupied_count() -> int:
	var count: int = 0
	for slot_variant in board:
		if slot_variant != null:
			count += 1
	return count
