extends RefCounted

const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const DIRECTIONS := [
	{"offset": -3, "side": 0, "opposite": 2},
	{"offset": 1, "side": 1, "opposite": 3},
	{"offset": 3, "side": 2, "opposite": 0},
	{"offset": -1, "side": 3, "opposite": 1},
]


func choose_move(match_state, card_owner: int, rng: RandomNumberGenerator, ai_profile: Resource = null) -> Dictionary:
	var hand: Array = match_state.get_hand(card_owner)
	var empty_cells: Array = match_state.get_empty_cells()
	if hand.is_empty() or empty_cells.is_empty():
		return {"valid": false}

	var capture_weight: float = _profile_float(ai_profile, &"capture_weight", 100.0)
	var same_trigger_weight: float = _profile_float(ai_profile, &"same_trigger_weight", 65.0)
	var plus_trigger_weight: float = _profile_float(ai_profile, &"plus_trigger_weight", 65.0)
	var influence_weight: float = _profile_float(ai_profile, &"influence_weight", 8.0)
	var future_setup_weight: float = _profile_float(ai_profile, &"future_setup_weight", 6.0)
	var influence_source_capture_weight: float = _profile_float(
		ai_profile,
		&"influence_source_capture_weight",
		18.0
	)
	var vulnerability_weight: float = _profile_float(ai_profile, &"vulnerability_weight", 3.0)
	var positional_weight: float = _profile_float(ai_profile, &"positional_weight", 1.0)
	var card_strength_weight: float = _profile_float(ai_profile, &"card_strength_weight", 0.08)
	var conserve_cost_weight: float = _profile_float(ai_profile, &"conserve_cost_weight", 0.0)
	var rotate_spend_penalty: float = _profile_float(ai_profile, &"rotate_spend_penalty", 16.0)
	var randomness: float = _profile_float(ai_profile, &"randomness", 1.5)

	var best_score: float = -INF
	var candidates: Array[Dictionary] = []
	var rotation_options: Array[int] = [0]
	if match_state.can_rotate(card_owner):
		rotation_options.append(1)

	for hand_index in range(hand.size()):
		var card = hand[hand_index]
		for cell_index in empty_cells:
			for rotation in rotation_options:
				var preview: Dictionary = match_state.preview_move(card, card_owner, cell_index, rotation)
				if not bool(preview.get("valid", false)):
					continue
				var capture_count: int = int(preview.get("capture_count", 0))
				var move_score: float = float(capture_count) * capture_weight
				if bool(preview.get("same_triggered", false)):
					move_score += same_trigger_weight
				if bool(preview.get("plus_triggered", false)):
					move_score += plus_trigger_weight

				# Influence is not just an immediate "number of highlighted cells" bonus.
				# Value pressure on cards already in play, useful zone denial on empty cells,
				# and flipping an enemy Influence source. This makes control profiles plan
				# around the NEXT action instead of spraying pressure wherever it fits.
				move_score += _influence_tactical_value(
					match_state,
					card,
					card_owner,
					preview,
					influence_weight,
					future_setup_weight
				)
				move_score += (
					float(_captured_influence_sources(match_state, preview, card_owner))
					* influence_source_capture_weight
				)

				move_score += _positional_bonus(
					match_state,
					card,
					cell_index,
					rotation,
					card_owner
				) * positional_weight
				move_score += float(card.rank_total()) * card_strength_weight

				# Deck cost is a construction constraint, not a resource spent during a
				# duel. The hook remains for experiments, but shipped profiles use zero;
				# otherwise the second player can artificially "bank" an expensive fifth
				# card in hand while still receiving its score point.
				move_score -= float(card.deck_cost) * conserve_cost_weight

				move_score -= _placement_vulnerability(
					match_state,
					card,
					cell_index,
					rotation,
					card_owner,
					preview
				) * vulnerability_weight

				if rotation != 0:
					move_score -= rotate_spend_penalty
				if randomness > 0.0:
					move_score += rng.randf_range(-randomness, randomness)

				if move_score > best_score + 0.001:
					best_score = move_score
					candidates = [{
						"hand_index": hand_index,
						"cell_index": cell_index,
						"rotate": rotation != 0,
					}]
				elif absf(move_score - best_score) <= 0.001:
					candidates.append({
						"hand_index": hand_index,
						"cell_index": cell_index,
						"rotate": rotation != 0,
					})

	if candidates.is_empty():
		return {"valid": false}
	var selected_index: int = rng.randi_range(0, candidates.size() - 1)
	var result: Dictionary = candidates[selected_index]
	result["valid"] = true
	return result


func _influence_tactical_value(
	match_state,
	card,
	card_owner: int,
	preview: Dictionary,
	influence_weight: float,
	future_setup_weight: float
) -> float:
	if card == null or not card.has_method("has_influence") or not bool(card.call("has_influence")):
		return 0.0
	var strength: int = maxi(1, int(card.get("influence_strength")))
	var score: float = (
		float(preview.get("influence_enemy_count", 0))
		* influence_weight
		* float(strength)
	)

	for raw_cell in preview.get("influence_cells", []):
		var cell_index: int = int(raw_cell)
		if cell_index < 0 or cell_index >= match_state.board.size():
			continue
		if match_state.board[cell_index] != null:
			continue
		# Empty pressure is zone denial: it is more useful around enemy cards and
		# in the center, where future placements usually touch more neighbors.
		var adjacent_enemies: int = _adjacent_enemy_count(
			match_state,
			cell_index,
			card_owner
		)
		var setup_value: float = 0.25 + float(adjacent_enemies) * 0.30
		if cell_index == 4:
			setup_value += 0.20
		score += setup_value * future_setup_weight * float(strength)
	return score


func _captured_influence_sources(
	match_state,
	preview: Dictionary,
	card_owner: int
) -> int:
	var count: int = 0
	for raw_cell in preview.get("captured", []):
		var cell_index: int = int(raw_cell)
		if cell_index < 0 or cell_index >= match_state.board.size():
			continue
		var slot_variant = match_state.board[cell_index]
		if slot_variant == null:
			continue
		var slot: Dictionary = slot_variant
		if int(slot.get("owner", 0)) == card_owner:
			continue
		var captured_card = slot.get("card", null)
		if (
			captured_card != null
			and captured_card.has_method("has_influence")
			and bool(captured_card.call("has_influence"))
		):
			count += 1
	return count


func _placement_vulnerability(
	match_state,
	card,
	cell_index: int,
	rotation: int,
	card_owner: int,
	preview: Dictionary
) -> float:
	var enemy_owner: int = _other_owner(card_owner)
	var enemy_hand: Array = match_state.get_hand(enemy_owner)
	if enemy_hand.is_empty():
		return 0.0

	var placed_modifier: int = int(preview.get("placed_total_modifier", 0))
	var projected_influence: Array = preview.get("influence_cells", [])
	var source_has_influence: bool = (
		card != null
		and card.has_method("has_influence")
		and bool(card.call("has_influence"))
	)
	var source_strength: int = (
		maxi(0, int(card.get("influence_strength")))
		if source_has_influence
		else 0
	)
	var enemy_can_rotate: bool = match_state.can_rotate(enemy_owner)
	var risk: float = 0.0

	for direction_variant in DIRECTIONS:
		var direction: Dictionary = direction_variant
		var side: int = int(direction["side"])
		var neighbor_index: int = cell_index + int(direction["offset"])
		if not _is_valid_neighbor(cell_index, neighbor_index, side):
			continue
		# Occupied neighbors cannot immediately receive the opponent's reply card.
		if match_state.board[neighbor_index] != null:
			continue

		var placed_rank: int = clampi(
			int(card.call("rank_for_side_rotated", side, rotation))
			+ placed_modifier,
			1,
			10
		)
		var best_enemy_rank: int = 0
		for hand_index in range(enemy_hand.size()):
			var enemy_card = enemy_hand[hand_index]
			var base_rotation: int = match_state.get_hand_rotation(enemy_owner, hand_index)
			var rotation_checks: Array[int] = [base_rotation]
			if enemy_can_rotate:
				rotation_checks.append(posmod(base_rotation + 1, 4))
			for enemy_rotation in rotation_checks:
				var candidate_rank: int = int(match_state.effective_rank_for_card(
					enemy_card,
					int(direction["opposite"]),
					int(enemy_rotation),
					neighbor_index,
					enemy_owner
				))
				# The previewed source is not yet on match_state.board, so account for
				# its Pressure manually when estimating the opponent's immediate reply.
				if source_strength > 0 and projected_influence.has(neighbor_index):
					candidate_rank = maxi(1, candidate_rank - source_strength)
				best_enemy_rank = maxi(best_enemy_rank, candidate_rank)

		if best_enemy_rank > placed_rank:
			risk += 1.0 + float(best_enemy_rank - placed_rank) * 0.25

	# Losing an Influence source is worse than losing an ordinary card because
	# its field changes allegiance on the next action.
	if source_has_influence:
		risk *= 1.35
	return risk


func _adjacent_enemy_count(match_state, cell_index: int, card_owner: int) -> int:
	var count: int = 0
	for direction_variant in DIRECTIONS:
		var direction: Dictionary = direction_variant
		var side: int = int(direction["side"])
		var neighbor_index: int = cell_index + int(direction["offset"])
		if not _is_valid_neighbor(cell_index, neighbor_index, side):
			continue
		var slot_variant = match_state.board[neighbor_index]
		if slot_variant == null:
			continue
		var slot: Dictionary = slot_variant
		if int(slot.get("owner", 0)) == _other_owner(card_owner):
			count += 1
	return count


func _positional_bonus(match_state, card, cell_index: int, rotation: int, card_owner: int) -> float:
	# Reward strong values on exposed edges. Different profiles scale this term,
	# which is enough to make a defensive opponent visibly prefer safer geometry.
	var row: int = floori(float(cell_index) / 3.0)
	var column: int = cell_index % 3
	var bonus: float = 0.0
	if row == 0:
		bonus += float(match_state.effective_rank_for_card(card, 0, rotation, cell_index, card_owner)) * 0.4
	if row == 2:
		bonus += float(match_state.effective_rank_for_card(card, 2, rotation, cell_index, card_owner)) * 0.4
	if column == 0:
		bonus += float(match_state.effective_rank_for_card(card, 3, rotation, cell_index, card_owner)) * 0.4
	if column == 2:
		bonus += float(match_state.effective_rank_for_card(card, 1, rotation, cell_index, card_owner)) * 0.4
	return bonus


func _is_valid_neighbor(cell_index: int, neighbor_index: int, side: int) -> bool:
	if neighbor_index < 0 or neighbor_index >= 9:
		return false
	var row: int = floori(float(cell_index) / 3.0)
	var column: int = cell_index % 3
	match side:
		0:
			return row > 0
		1:
			return column < 2
		2:
			return row < 2
		3:
			return column > 0
		_:
			return false


func _other_owner(card_owner: int) -> int:
	return OWNER_OPPONENT if card_owner == OWNER_PLAYER else OWNER_PLAYER


func _profile_float(profile: Resource, property_name: StringName, fallback: float) -> float:
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	if value == null:
		return fallback
	return float(value)
