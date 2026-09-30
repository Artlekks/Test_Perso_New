extends RefCounted


func choose_move(match_state, card_owner: int, rng: RandomNumberGenerator, ai_profile: Resource = null) -> Dictionary:
	var hand: Array = match_state.get_hand(card_owner)
	var empty_cells: Array = match_state.get_empty_cells()
	if hand.is_empty() or empty_cells.is_empty():
		return {"valid": false}

	var capture_weight: float = _profile_float(ai_profile, &"capture_weight", 100.0)
	var same_trigger_weight: float = _profile_float(ai_profile, &"same_trigger_weight", 65.0)
	var plus_trigger_weight: float = _profile_float(ai_profile, &"plus_trigger_weight", 65.0)
	var positional_weight: float = _profile_float(ai_profile, &"positional_weight", 1.0)
	var card_strength_weight: float = _profile_float(ai_profile, &"card_strength_weight", 0.08)
	var conserve_cost_weight: float = _profile_float(ai_profile, &"conserve_cost_weight", 0.3)
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
				move_score += _positional_bonus(match_state, card, cell_index, rotation) * positional_weight
				move_score += float(card.rank_total()) * card_strength_weight
				move_score -= float(card.deck_cost) * conserve_cost_weight
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


func _positional_bonus(match_state, card, cell_index: int, rotation: int) -> float:
	# Reward strong values on exposed edges. Different profiles scale this term,
	# which is enough to make a defensive opponent visibly prefer safer geometry.
	var row: int = floori(float(cell_index) / 3.0)
	var column: int = cell_index % 3
	var bonus: float = 0.0
	if row == 0:
		bonus += float(match_state.effective_rank_for_card(card, 0, rotation, cell_index)) * 0.4
	if row == 2:
		bonus += float(match_state.effective_rank_for_card(card, 2, rotation, cell_index)) * 0.4
	if column == 0:
		bonus += float(match_state.effective_rank_for_card(card, 3, rotation, cell_index)) * 0.4
	if column == 2:
		bonus += float(match_state.effective_rank_for_card(card, 1, rotation, cell_index)) * 0.4
	return bonus


func _profile_float(profile: Resource, property_name: StringName, fallback: float) -> float:
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	if value == null:
		return fallback
	return float(value)
