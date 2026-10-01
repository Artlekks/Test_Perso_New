extends RefCounted


func choose_lost_card_index(cards: Array) -> int:
	if cards.is_empty():
		return -1

	var best_index: int = 0
	for index in range(1, cards.size()):
		if _is_stronger(cards[index], cards[best_index]):
			best_index = index
	return best_index


func _is_stronger(candidate, incumbent) -> bool:
	if candidate == null:
		return false
	if incumbent == null:
		return true

	var candidate_points: int = int(candidate.get("deck_cost"))
	var incumbent_points: int = int(incumbent.get("deck_cost"))
	if candidate_points != incumbent_points:
		return candidate_points > incumbent_points

	var candidate_total: int = _rank_total(candidate)
	var incumbent_total: int = _rank_total(incumbent)
	if candidate_total != incumbent_total:
		return candidate_total > incumbent_total

	# Stable deterministic final tie-breaker. Lower stable ID wins the tie so the
	# result never depends on hand array ordering or hash iteration order.
	return String(candidate.get("card_id")) < String(incumbent.get("card_id"))


func _rank_total(card) -> int:
	if card != null and card.has_method("rank_total"):
		return int(card.call("rank_total"))
	if card == null:
		return 0
	return (
		int(card.get("top_rank"))
		+ int(card.get("right_rank"))
		+ int(card.get("bottom_rank"))
		+ int(card.get("left_rank"))
	)
