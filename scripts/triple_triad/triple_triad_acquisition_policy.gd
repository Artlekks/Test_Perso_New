extends Resource
class_name TripleTriadAcquisitionPolicy

@export_category("Starter Collection")
## New saves only. Existing collections are never reset by changing this value.
@export_range(5, 100, 1) var starter_collection_size: int = 10
@export var starter_required_tag: StringName = &"starter"
@export_range(1, 10, 1) var starter_player_rank: int = 1

@export_category("Ownership")
@export var allow_duplicate_ownership: bool = true

@export_category("Rank Gating")
## Ownership is allowed at any rank. This flag controls whether a card above the
## player's Duel Rank can be placed in a saved/match deck.
@export var enforce_card_rank_for_decks: bool = true


func build_starting_collection(catalog: Resource) -> Array:
	var candidates: Array = []
	if catalog == null:
		return candidates

	if (
		starter_required_tag != &""
		and catalog.has_method("get_cards_with_acquisition_tag")
	):
		candidates = catalog.call(
			"get_cards_with_acquisition_tag",
			starter_required_tag,
			starter_player_rank
		)
	elif catalog.has_method("get_cards_for_player_rank"):
		candidates = catalog.call(
			"get_cards_for_player_rank",
			starter_player_rank
		)

	candidates.sort_custom(func(a, b):
		var points_a: int = int(a.deck_cost)
		var points_b: int = int(b.deck_cost)
		if points_a == points_b:
			var total_a: int = int(a.rank_total())
			var total_b: int = int(b.rank_total())
			if total_a == total_b:
				return String(a.card_id) < String(b.card_id)
			return total_a < total_b
		return points_a < points_b
	)

	var result: Array = []
	var seen: Dictionary = {}
	for card in candidates:
		if card == null:
			continue
		var card_id := StringName(card.card_id)
		if seen.has(card_id):
			continue
		result.append(card)
		seen[card_id] = true
		if result.size() >= starter_collection_size:
			break
	return result


func can_use_card(card, player_rank: int) -> bool:
	if card == null:
		return false
	if not enforce_card_rank_for_decks:
		return true
	if card.has_method("is_usable_at_player_rank"):
		return bool(card.call("is_usable_at_player_rank", player_rank))
	return true


func get_card_lock_reason(card, player_rank: int) -> String:
	if can_use_card(card, player_rank):
		return ""
	if card == null:
		return "Card unavailable."
	var required_rank: int = int(card.get("required_player_rank"))
	return "Requires Duel Rank %d." % maxi(1, required_rank)
