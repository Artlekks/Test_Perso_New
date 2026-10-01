extends RefCounted


func choose_lost_card_index(
	cards: Array,
	playable_owned_cards: Array = [],
	owned_quantities: Dictionary = {},
	minimum_playable_unique_cards: int = 0
) -> int:
	if cards.is_empty():
		return -1

	var safe_candidates: Array[int] = []
	for index in range(cards.size()):
		var card = cards[index]
		if _is_safe_to_lose(
			card,
			playable_owned_cards,
			owned_quantities,
			minimum_playable_unique_cards
		):
			safe_candidates.append(index)

	if safe_candidates.is_empty():
		return -1

	var best_index: int = safe_candidates[0]
	for candidate_index in safe_candidates.slice(1):
		if _is_stronger(cards[candidate_index], cards[best_index]):
			best_index = candidate_index
	return best_index


func _is_safe_to_lose(
	card,
	playable_owned_cards: Array,
	owned_quantities: Dictionary,
	minimum_playable_unique_cards: int
) -> bool:
	# Compatibility mode for callers/tests that only want "strongest card".
	if minimum_playable_unique_cards <= 0 or playable_owned_cards.is_empty():
		return true
	if card == null:
		return false

	var card_id: String = String(card.get("card_id"))
	var quantity: int = maxi(0, int(owned_quantities.get(card_id, 1)))

	# Losing one duplicate copy does not reduce the set of playable unique cards.
	if quantity > 1:
		return true

	var playable_ids: Dictionary = {}
	for playable_card in playable_owned_cards:
		if playable_card == null:
			continue
		playable_ids[String(playable_card.get("card_id"))] = true

	var playable_unique_count: int = playable_ids.size()
	if not playable_ids.has(card_id):
		# A non-playable card can never invalidate the player's current legal deck.
		return true

	return (
		playable_unique_count - 1
		>= maxi(1, minimum_playable_unique_cards)
	)


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
