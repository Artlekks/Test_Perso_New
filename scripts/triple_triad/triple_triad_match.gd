extends RefCounted

const InfluenceResolverScript = preload("res://scripts/triple_triad/triple_triad_influence_resolver.gd")

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
var _influence_resolver = InfluenceResolverScript.new()
var _resolution_influence_state: Dictionary = {}
var _resolution_influence_modifiers: Dictionary = {}


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
	_resolution_influence_state.clear()
	_resolution_influence_modifiers.clear()


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

	var influence_state: Dictionary = _build_influence_state()
	var projected_influence: Array[int] = get_influence_cells_for_card(
		card,
		cell_index,
		card_rotation
	)
	var influence_modifiers: Dictionary = _occupied_influence_modifiers(influence_state)
	var capture_result: Dictionary = _resolve_captures(
		cell_index,
		card_owner,
		influence_state
	)
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
		"plus_captured": capture_result["plus_captured"],
		"combo_captured": capture_result["combo_captured"],
		"same_match_count": capture_result["same_match_count"],
		"plus_match_count": capture_result["plus_match_count"],
		"same_triggered": capture_result["same_triggered"],
		"plus_triggered": capture_result["plus_triggered"],
		"influence_cells": projected_influence,
		"influence_modifiers": influence_modifiers,
		"placed_total_modifier": (
			get_cell_rank_bonus(cell_index)
			+ _influence_resolver.modifier_for_cell(
				influence_state,
				cell_index,
				card_owner
			)
		),
		"game_over": game_over,
		"score": get_score(),
		"winner": get_winner(),
	}


func preview_move(
	card,
	card_owner: int,
	cell_index: int,
	rotation_quarters: int = 0
) -> Dictionary:
	if (
		card == null
		or cell_index < 0
		or cell_index >= board.size()
		or board[cell_index] != null
	):
		return {
			"valid": false,
			"captured": [],
			"capture_count": -1,
			"same_triggered": false,
			"plus_triggered": false,
			"same_match_count": 0,
			"plus_match_count": 0,
			"influence_cells": [],
			"influence_modifiers": {},
			"influence_before": get_influence_board_snapshot(),
			"influence_resolution": [],
			"influence_next_action": [],
			"influence_deltas": [],
			"placed_total_modifier": 0,
		}

	var original_board: Array = board
	var influence_before: Array = get_influence_board_snapshot()
	board = board.duplicate(true)
	var clean_rotation: int = posmod(rotation_quarters, 4)
	board[cell_index] = {
		"card": card,
		"owner": card_owner,
		"rotation": clean_rotation,
	}

	var influence_state: Dictionary = _build_influence_state()
	var influence_resolution: Array = _build_influence_board_snapshot(
		influence_state
	)
	var projected_influence: Array[int] = get_influence_cells_for_card(
		card,
		cell_index,
		clean_rotation
	)
	var influence_modifiers: Dictionary = _occupied_influence_modifiers(
		influence_state
	)
	var placed_total_modifier: int = (
		get_cell_rank_bonus(cell_index)
		+ _influence_resolver.modifier_for_cell(
			influence_state,
			cell_index,
			card_owner
		)
	)
	var capture_result: Dictionary = _resolve_captures(
		cell_index,
		card_owner,
		influence_state
	)

	# Ownership changes caused by this move affect the field on the NEXT action,
	# never halfway through the current resolution. Exposing both snapshots lets
	# the UI explain that rule without reimplementing gameplay math.
	_resolution_influence_state.clear()
	_resolution_influence_modifiers.clear()
	var influence_next_action: Array = _build_influence_board_snapshot(
		_build_influence_state()
	)
	var influence_deltas: Array = _build_influence_deltas(
		influence_before,
		influence_resolution
	)

	board = original_board
	_resolution_influence_state.clear()
	_resolution_influence_modifiers.clear()
	return {
		"valid": true,
		"cell_index": cell_index,
		"rotation": clean_rotation,
		"captured": capture_result["captured"],
		"capture_count": (capture_result["captured"] as Array).size(),
		"basic_captured": capture_result["basic_captured"],
		"same_captured": capture_result["same_captured"],
		"plus_captured": capture_result["plus_captured"],
		"combo_captured": capture_result["combo_captured"],
		"same_triggered": capture_result["same_triggered"],
		"plus_triggered": capture_result["plus_triggered"],
		"same_match_count": capture_result["same_match_count"],
		"plus_match_count": capture_result["plus_match_count"],
		"influence_cells": projected_influence,
		"influence_modifiers": influence_modifiers,
		"influence_before": influence_before,
		"influence_resolution": influence_resolution,
		"influence_next_action": influence_next_action,
		"influence_deltas": influence_deltas,
		"influence_enemy_count": _count_influenced_enemies(
			projected_influence,
			card_owner
		),
		"influence_empty_count": _count_influenced_empty_cells(
			projected_influence
		),
		"placed_total_modifier": placed_total_modifier,
	}


func preview_capture_count(card, card_owner: int, cell_index: int, rotation_quarters: int = 0) -> int:
	var preview: Dictionary = preview_move(card, card_owner, cell_index, rotation_quarters)
	return int(preview.get("capture_count", -1))


func effective_rank_for_card(
	card,
	side: int,
	rotation_quarters: int = 0,
	cell_index: int = -1,
	card_owner: int = OWNER_NONE
) -> int:
	if card == null:
		return 0
	var base_rank: int
	if card.has_method("rank_for_side_rotated"):
		base_rank = int(card.rank_for_side_rotated(side, rotation_quarters))
	else:
		base_rank = int(card.rank_for_side(side))
	var modifier: int = get_cell_rank_bonus(cell_index)
	if card_owner in [OWNER_PLAYER, OWNER_OPPONENT]:
		modifier += get_cell_influence_modifier(cell_index, card_owner)
	return clampi(base_rank + modifier, 1, 10)


func get_cell_rank_bonus(cell_index: int) -> int:
	if region_profile == null or cell_index < 0 or cell_index >= 9:
		return 0
	if region_profile.has_method("rank_bonus_for_cell"):
		return int(region_profile.call("rank_bonus_for_cell", cell_index))
	return 0


func get_cell_influence_modifier(cell_index: int, card_owner: int) -> int:
	if not _influence_enabled() or cell_index < 0 or cell_index >= board.size():
		return 0

	# During one placement, both source influence and the modifiers already applied
	# to occupied cards are frozen before any capture changes ownership. This keeps
	# Same/Plus/Basic/Combo deterministic and prevents a card from gaining or losing
	# pressure halfway through the same resolution just because it flipped sides.
	if not _resolution_influence_state.is_empty():
		return int(_resolution_influence_modifiers.get(cell_index, 0))

	var state: Dictionary = _build_influence_state()
	return _influence_resolver.modifier_for_cell(state, cell_index, card_owner)


func get_influence_cells_for_card(
	card,
	source_cell: int,
	rotation_quarters: int = 0
) -> Array[int]:
	if not _influence_enabled():
		return []
	return _influence_resolver.projected_cells(
		card,
		source_cell,
		rotation_quarters,
		board.size()
	)


func get_current_influence_modifiers() -> Dictionary:
	return _occupied_influence_modifiers(_build_influence_state())


func get_influence_board_snapshot() -> Array:
	return _build_influence_board_snapshot(_build_influence_state())


func _build_influence_board_snapshot(state: Dictionary) -> Array:
	var result: Array = []
	for cell_index in range(board.size()):
		var slot_variant = board[cell_index]
		var owner: int = OWNER_NONE
		var card = null
		var rotation: int = 0
		if slot_variant != null:
			var slot: Dictionary = slot_variant
			owner = int(slot.get("owner", OWNER_NONE))
			card = slot.get("card", null)
			rotation = int(slot.get("rotation", 0))

		var influence: Dictionary = _influence_resolver.cell_snapshot(
			state,
			cell_index,
			owner
		)
		var region_bonus: int = get_cell_rank_bonus(cell_index)
		var modifier: int = int(influence.get("modifier", 0))
		var printed_ranks: Array[int] = []
		var effective_ranks: Array[int] = []
		if card != null:
			for side in range(4):
				var printed: int = _card_rank_rotated(
					card,
					side,
					rotation
				)
				printed_ranks.append(printed)
				effective_ranks.append(
					clampi(printed + region_bonus + modifier, 1, 10)
				)

		result.append({
			"cell_index": cell_index,
			"occupied": card != null,
			"owner": owner,
			"card_id": String(card.get("card_id")) if card != null else "",
			"display_name": str(card.get("display_name")) if card != null else "",
			"rotation": rotation,
			"region_bonus": region_bonus,
			"influence_modifier": modifier,
			"printed_ranks": printed_ranks,
			"effective_ranks": effective_ranks,
			"player_pressure": int(influence.get("player_pressure", 0)),
			"opponent_pressure": int(influence.get("opponent_pressure", 0)),
			"player_sources": influence.get("player_sources", []),
			"opponent_sources": influence.get("opponent_sources", []),
			"opposing_sources": influence.get("opposing_sources", []),
		})
	return result


func _build_influence_deltas(before: Array, after: Array) -> Array:
	var result: Array = []
	var cell_count: int = mini(before.size(), after.size())
	for cell_index in range(cell_count):
		var before_cell: Dictionary = before[cell_index]
		var after_cell: Dictionary = after[cell_index]
		var before_modifier: int = int(
			before_cell.get("influence_modifier", 0)
		)
		var after_modifier: int = int(
			after_cell.get("influence_modifier", 0)
		)
		var before_ranks: Array = before_cell.get("effective_ranks", [])
		var after_ranks: Array = after_cell.get("effective_ranks", [])
		var changed: bool = (
			before_modifier != after_modifier
			or before_ranks != after_ranks
			or bool(before_cell.get("occupied", false))
			!= bool(after_cell.get("occupied", false))
		)
		if not changed:
			continue
		result.append({
			"cell_index": cell_index,
			"before_modifier": before_modifier,
			"after_modifier": after_modifier,
			"modifier_delta": after_modifier - before_modifier,
			"before_effective_ranks": before_ranks.duplicate(),
			"after_effective_ranks": after_ranks.duplicate(),
			"before_occupied": bool(before_cell.get("occupied", false)),
			"after_occupied": bool(after_cell.get("occupied", false)),
			"after_card_id": str(after_cell.get("card_id", "")),
			"opposing_sources": (
				after_cell.get("opposing_sources", []) as Array
			).duplicate(true),
		})
	return result


func _card_rank_rotated(card, side: int, rotation: int) -> int:
	if card == null:
		return 0
	if card.has_method("rank_for_side_rotated"):
		return int(card.call("rank_for_side_rotated", side, rotation))
	return int(card.call("rank_for_side", side))


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


func _resolve_captures(
	cell_index: int,
	card_owner: int,
	influence_state: Dictionary = {}
) -> Dictionary:
	_resolution_influence_state = (
		influence_state
		if not influence_state.is_empty()
		else _build_influence_state()
	)
	_resolution_influence_modifiers = _occupied_influence_modifiers(
		_resolution_influence_state
	)
	var same_result: Dictionary = _resolve_same_captures(cell_index, card_owner)
	var plus_result: Dictionary = _resolve_plus_captures(cell_index, card_owner)

	var same_captured: Array[int] = []
	same_captured.assign(same_result.get("captured", []))
	var plus_captured: Array[int] = []
	plus_captured.assign(plus_result.get("captured", []))

	var basic_captured: Array[int] = _resolve_basic_captures(cell_index, card_owner)

	# Only cards flipped by a special rule seed Combo. Same and Plus can both
	# trigger on the same placement, so merge their seeds without duplicates.
	var combo_seeds: Array[int] = []
	_append_unique_cells(combo_seeds, same_captured)
	_append_unique_cells(combo_seeds, plus_captured)

	var combo_captured: Array[int] = []
	if _rule_enabled("combo_rule") and not combo_seeds.is_empty():
		combo_captured = _resolve_combo_captures(combo_seeds, card_owner)

	var captured: Array[int] = []
	_append_unique_cells(captured, same_captured)
	_append_unique_cells(captured, plus_captured)
	_append_unique_cells(captured, basic_captured)
	_append_unique_cells(captured, combo_captured)
	_resolution_influence_state.clear()
	_resolution_influence_modifiers.clear()
	return {
		"captured": captured,
		"basic_captured": basic_captured,
		"same_captured": same_captured,
		"plus_captured": plus_captured,
		"combo_captured": combo_captured,
		"same_match_count": int(same_result["match_count"]),
		"plus_match_count": int(plus_result["match_count"]),
		"same_triggered": bool(same_result["triggered"]),
		"plus_triggered": bool(plus_result["triggered"]),
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


func _resolve_plus_captures(cell_index: int, card_owner: int) -> Dictionary:
	if not _rule_enabled("plus_rule"):
		return {"captured": [], "match_count": 0, "triggered": false}

	var placed_slot: Dictionary = board[cell_index]
	var neighbors_by_sum: Dictionary = {}

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
		var rank_sum: int = (
			_slot_rank(placed_slot, side, cell_index)
			+ _slot_rank(neighbor, int(direction["opposite"]), neighbor_index)
		)
		if not neighbors_by_sum.has(rank_sum):
			neighbors_by_sum[rank_sum] = []
		var group: Array = neighbors_by_sum[rank_sum]
		group.append(neighbor_index)
		neighbors_by_sum[rank_sum] = group

	var matching_neighbors: Array[int] = []
	for raw_sum in neighbors_by_sum.keys():
		var group: Array = neighbors_by_sum[raw_sum]
		if group.size() < 2:
			continue
		for neighbor_index in group:
			if not matching_neighbors.has(int(neighbor_index)):
				matching_neighbors.append(int(neighbor_index))

	if matching_neighbors.size() < 2:
		return {
			"captured": [],
			"match_count": matching_neighbors.size(),
			"triggered": false,
		}

	var captured: Array[int] = []
	for neighbor_index in matching_neighbors:
		var neighbor: Dictionary = board[neighbor_index]
		if int(neighbor["owner"]) == card_owner:
			continue
		neighbor["owner"] = card_owner
		board[neighbor_index] = neighbor
		captured.append(neighbor_index)

	return {
		"captured": captured,
		"match_count": matching_neighbors.size(),
		"triggered": true,
	}


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
	return effective_rank_for_card(card, side, rotation, cell_index, int(slot.get("owner", OWNER_NONE)))


func _influence_enabled() -> bool:
	return _rule_enabled("influence_rule")


func _build_influence_state() -> Dictionary:
	return _influence_resolver.build_state(board, _influence_enabled())


func _occupied_influence_modifiers(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if not _influence_enabled():
		return result
	for cell_index in range(board.size()):
		var slot_variant = board[cell_index]
		if slot_variant == null:
			continue
		var slot: Dictionary = slot_variant
		var owner: int = int(slot.get("owner", OWNER_NONE))
		var modifier: int = _influence_resolver.modifier_for_cell(
			state,
			cell_index,
			owner
		)
		if modifier != 0:
			result[cell_index] = modifier
	return result


func _count_influenced_enemies(cells: Array[int], source_owner: int) -> int:
	var count: int = 0
	for cell_index in cells:
		if cell_index < 0 or cell_index >= board.size():
			continue
		var slot_variant = board[cell_index]
		if slot_variant == null:
			continue
		var slot: Dictionary = slot_variant
		if int(slot.get("owner", OWNER_NONE)) == _other_owner(source_owner):
			count += 1
	return count


func _count_influenced_empty_cells(cells: Array[int]) -> int:
	var count: int = 0
	for cell_index in cells:
		if cell_index >= 0 and cell_index < board.size() and board[cell_index] == null:
			count += 1
	return count


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
