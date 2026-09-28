extends RefCounted


func choose_move(match_state, owner: int, rng: RandomNumberGenerator) -> Dictionary:
	var hand: Array = match_state.get_hand(owner)
	var empty_cells: Array = match_state.get_empty_cells()
	if hand.is_empty() or empty_cells.is_empty():
		return {"valid": false}

	var best_score: float = -INF
	var candidates: Array[Dictionary] = []
	for hand_index in range(hand.size()):
		var card = hand[hand_index]
		for cell_index in empty_cells:
			var capture_count: int = match_state.preview_capture_count(card, owner, cell_index)
			var positional_bonus: float = _positional_bonus(card, cell_index)
			var value_score: float = float(card.rank_total()) * 0.08
			var move_score: float = float(capture_count) * 100.0 + positional_bonus + value_score
			if move_score > best_score + 0.001:
				best_score = move_score
				candidates = [{"hand_index": hand_index, "cell_index": cell_index}]
			elif absf(move_score - best_score) <= 0.001:
				candidates.append({"hand_index": hand_index, "cell_index": cell_index})

	if candidates.is_empty():
		return {"valid": false}
	var selected_index: int = rng.randi_range(0, candidates.size() - 1)
	var result: Dictionary = candidates[selected_index]
	result["valid"] = true
	return result


func _positional_bonus(card, cell_index: int) -> float:
	# Mildly prefer corners/edges when the exposed ranks are strong. This remains
	# deliberately simple; the AI is a replaceable strategy object.
	var row: int = floori(float(cell_index) / 3.0)
	var column: int = cell_index % 3
	var bonus: float = 0.0
	if row == 0:
		bonus += float(card.top_rank) * 0.4
	if row == 2:
		bonus += float(card.bottom_rank) * 0.4
	if column == 0:
		bonus += float(card.left_rank) * 0.4
	if column == 2:
		bonus += float(card.right_rank) * 0.4
	return bonus
