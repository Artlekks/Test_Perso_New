extends RefCounted

const SAVE_PATH := "user://triple_triad_opponents.cfg"
const SAVE_VERSION := 1
const HAND_SIZE := 5
const INITIAL_COLLECTION_SIZE := 15

var _catalog: Resource = null
var _opponent_id: StringName = &"opponent"
var _min_level: int = 1
var _max_level: int = 3
var _budget: int = 30
var _quantities: Dictionary = {}
var _deck_ids: Array = []
var _priority_ids: Array = []


func initialize(
	catalog: Resource,
	opponent_id: StringName,
	min_level: int,
	max_level: int,
	budget: int
) -> void:
	_catalog = catalog
	_opponent_id = opponent_id if not String(opponent_id).is_empty() else &"opponent"
	_min_level = clampi(min_level, 1, 10)
	_max_level = clampi(max_level, _min_level, 10)
	_budget = maxi(5, budget)
	_quantities.clear()
	_deck_ids.clear()
	_priority_ids.clear()

	var config := ConfigFile.new()
	var load_error: Error = config.load(SAVE_PATH)
	var meta_section: String = _meta_section()
	var cards_section: String = _cards_section()
	var has_saved_data: bool = (
		load_error == OK
		and config.has_section(meta_section)
		and int(config.get_value(meta_section, "version", 0)) > 0
	)

	if has_saved_data:
		if config.has_section(cards_section):
			for raw_key in config.get_section_keys(cards_section):
				var card_id := StringName(str(raw_key))
				var quantity: int = maxi(0, int(config.get_value(cards_section, raw_key, 0)))
				if quantity > 0:
					_quantities[card_id] = quantity

		var raw_deck = config.get_value(meta_section, "deck_ids", PackedStringArray())
		if raw_deck is PackedStringArray or raw_deck is Array:
			for raw_id in raw_deck:
				_deck_ids.append(StringName(str(raw_id)))

		var raw_priority = config.get_value(meta_section, "priority_ids", PackedStringArray())
		if raw_priority is PackedStringArray or raw_priority is Array:
			for raw_id in raw_priority:
				_priority_ids.append(StringName(str(raw_id)))
	else:
		_seed_initial_collection()

	_sanitize()
	_save()


func build_match_deck(hand_size: int = HAND_SIZE, budget: int = 30) -> Array:
	_budget = maxi(5, budget)
	var target_size: int = maxi(1, hand_size)
	var ordered_ids: Array = []
	_append_unique_ids(ordered_ids, _priority_ids)
	_append_unique_ids(ordered_ids, _deck_ids)

	var owned_cards: Array = get_owned_cards()
	owned_cards.sort_custom(func(card_a, card_b):
		var cost_a: int = int(card_a.deck_cost)
		var cost_b: int = int(card_b.deck_cost)
		if cost_a == cost_b:
			var strength_a: int = int(card_a.rank_total()) if card_a.has_method("rank_total") else 0
			var strength_b: int = int(card_b.rank_total()) if card_b.has_method("rank_total") else 0
			if strength_a == strength_b:
				return String(card_a.card_id) < String(card_b.card_id)
			return strength_a > strength_b
		return cost_a < cost_b
	)
	for card in owned_cards:
		var card_id := StringName(card.card_id)
		if not ordered_ids.has(card_id):
			ordered_ids.append(card_id)

	var result: Array = []
	var running_cost: int = 0
	for raw_id in ordered_ids:
		if result.size() >= target_size:
			break
		var card = _card_for_id(StringName(raw_id))
		if card == null or not owns_card(card):
			continue
		if _contains_card_id(result, StringName(card.card_id)):
			continue
		var card_cost: int = int(card.deck_cost)
		if running_cost + card_cost > _budget:
			continue
		result.append(card)
		running_cost += card_cost

	# The profile should normally have enough legal cards to satisfy its budget.
	# If authored data later creates an impossible budget, still return a full hand
	# rather than breaking the match. The UI/game can surface the tuning issue.
	if result.size() < target_size:
		for card in owned_cards:
			if result.size() >= target_size:
				break
			if _contains_card_id(result, StringName(card.card_id)):
				continue
			result.append(card)

	_deck_ids.clear()
	for card in result:
		_deck_ids.append(StringName(card.card_id))
	_trim_priority_ids()
	_save()
	return result


func acquire_card(card, make_priority: bool = true) -> int:
	if card == null:
		return 0
	var card_id := StringName(card.card_id)
	var new_quantity: int = get_quantity_by_id(card_id) + 1
	_quantities[card_id] = new_quantity

	if make_priority:
		_priority_ids.erase(card_id)
		_priority_ids.push_front(card_id)

		# Put a newly won player card straight into the opponent's saved deck.
		# The next build_match_deck() keeps it first, which guarantees the player
		# gets a real chance to win their card back from this same NPC.
		_deck_ids.erase(card_id)
		_deck_ids.push_front(card_id)
		while _deck_ids.size() > HAND_SIZE:
			_deck_ids.pop_back()

	_save()
	return new_quantity


func remove_card(card) -> int:
	if card == null:
		return 0
	var card_id := StringName(card.card_id)
	var current_quantity: int = get_quantity_by_id(card_id)
	var new_quantity: int = maxi(0, current_quantity - 1)
	if new_quantity <= 0:
		_quantities.erase(card_id)
		_deck_ids.erase(card_id)
		_priority_ids.erase(card_id)
	else:
		_quantities[card_id] = new_quantity
	_save()
	return new_quantity


func owns_card(card) -> bool:
	if card == null:
		return false
	return get_quantity_by_id(StringName(card.card_id)) > 0


func get_quantity_by_id(card_id: StringName) -> int:
	return maxi(0, int(_quantities.get(card_id, 0)))


func get_owned_cards() -> Array:
	var result: Array = []
	if _catalog == null or not _catalog.has_method("get_total_source_count"):
		return result
	for source_index in range(int(_catalog.call("get_total_source_count"))):
		var card = _catalog.call("get_card", source_index)
		if card != null and owns_card(card):
			result.append(card)
	return result


func _seed_initial_collection() -> void:
	_quantities.clear()
	_deck_ids.clear()
	_priority_ids.clear()
	if _catalog == null or not _catalog.has_method("get_cards_for_level_range"):
		return

	var candidates: Array = _catalog.call(
		"get_cards_for_level_range",
		_min_level,
		_max_level
	)
	candidates.sort_custom(func(card_a, card_b):
		return _stable_seed_value(card_a) < _stable_seed_value(card_b)
	)

	var seed_count: int = mini(INITIAL_COLLECTION_SIZE, candidates.size())
	for index in range(seed_count):
		var card = candidates[index]
		if card == null:
			continue
		var card_id := StringName(card.card_id)
		_quantities[card_id] = 1

	# Build a legal five-card baseline from the seeded collection.
	var initial_deck: Array = build_match_deck(HAND_SIZE, _budget)
	_deck_ids.clear()
	for card in initial_deck:
		_deck_ids.append(StringName(card.card_id))


func _sanitize() -> void:
	if _catalog == null or not _catalog.has_method("get_card_by_id"):
		return

	var invalid_ids: Array = []
	for raw_id in _quantities.keys():
		var card_id := StringName(raw_id)
		if _card_for_id(card_id) == null:
			invalid_ids.append(card_id)
	for card_id in invalid_ids:
		_quantities.erase(card_id)

	var clean_deck: Array = []
	for raw_id in _deck_ids:
		var card_id := StringName(raw_id)
		if get_quantity_by_id(card_id) > 0 and _card_for_id(card_id) != null and not clean_deck.has(card_id):
			clean_deck.append(card_id)
	_deck_ids = clean_deck

	_trim_priority_ids()


func _trim_priority_ids() -> void:
	var clean_priority: Array = []
	for raw_id in _priority_ids:
		var card_id := StringName(raw_id)
		if get_quantity_by_id(card_id) > 0 and _card_for_id(card_id) != null and not clean_priority.has(card_id):
			clean_priority.append(card_id)
	_priority_ids = clean_priority


func _append_unique_ids(target: Array, source: Array) -> void:
	for raw_id in source:
		var card_id := StringName(raw_id)
		if not target.has(card_id):
			target.append(card_id)


func _contains_card_id(cards: Array, card_id: StringName) -> bool:
	for card in cards:
		if card != null and String(card.card_id) == String(card_id):
			return true
	return false


func _card_for_id(card_id: StringName):
	if _catalog == null or not _catalog.has_method("get_card_by_id"):
		return null
	return _catalog.call("get_card_by_id", card_id)


func _stable_seed_value(card) -> int:
	if card == null:
		return 2147483647
	return abs(int(("%s:%s" % [String(_opponent_id), String(card.card_id)]).hash()))


func _meta_section() -> String:
	return "opponent_%s_meta" % String(_opponent_id)


func _cards_section() -> String:
	return "opponent_%s_cards" % String(_opponent_id)


func _save() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)

	var meta_section: String = _meta_section()
	var cards_section: String = _cards_section()
	if config.has_section(meta_section):
		config.erase_section(meta_section)
	if config.has_section(cards_section):
		config.erase_section(cards_section)

	config.set_value(meta_section, "version", SAVE_VERSION)
	config.set_value(meta_section, "deck_ids", _to_packed_string_array(_deck_ids))
	config.set_value(meta_section, "priority_ids", _to_packed_string_array(_priority_ids))

	for raw_id in _quantities.keys():
		var card_id := StringName(raw_id)
		var quantity: int = maxi(0, int(_quantities[card_id]))
		if quantity > 0:
			config.set_value(cards_section, String(card_id), quantity)

	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning("TripleTriadOpponentCollection: could not save NPC cards (%s)." % error_string(save_error))


func _to_packed_string_array(values: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for value in values:
		result.append(String(value))
	return result
