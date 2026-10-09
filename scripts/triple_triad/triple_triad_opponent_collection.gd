extends RefCounted

const Storage = preload("res://scripts/triple_triad/triple_triad_config_store.gd")

const SAVE_PATH := "user://triple_triad_opponents.cfg"
const SAVE_VERSION := 2
const HAND_SIZE := 5
const DEFAULT_INITIAL_COLLECTION_SIZE := 15

var _catalog: Resource = null
var _opponent_id: StringName = &"opponent"
var _min_level: int = 1
var _max_level: int = 3
var _budget: int = 30
var _initial_collection_size: int = DEFAULT_INITIAL_COLLECTION_SIZE
var _profile: Resource = null
var _profile_content_revision: int = 0
var _native_card_ids: Array = []
var _preferred_deck_ids: Array = []
var _quantities: Dictionary = {}
var _deck_ids: Array = []
var _priority_ids: Array = []
var _last_evolution_snapshot: Dictionary = {}


func initialize(
	catalog: Resource,
	opponent_id: StringName,
	min_level: int,
	max_level: int,
	budget: int,
	profile: Resource = null
) -> void:
	_catalog = catalog
	_opponent_id = opponent_id if not String(opponent_id).is_empty() else &"opponent"
	_min_level = clampi(min_level, 1, 10)
	_max_level = clampi(max_level, _min_level, 10)
	_budget = maxi(5, budget)
	_profile = profile
	_initial_collection_size = DEFAULT_INITIAL_COLLECTION_SIZE
	_native_card_ids.clear()
	_preferred_deck_ids.clear()
	_quantities.clear()
	_deck_ids.clear()
	_priority_ids.clear()
	_read_profile_data()

	var config := ConfigFile.new()
	var load_error: Error = config.load(SAVE_PATH)
	var meta_section: String = _meta_section()
	var cards_section: String = _cards_section()
	var has_saved_data: bool = (
		load_error == OK
		and config.has_section(meta_section)
		and int(config.get_value(meta_section, "version", 0)) > 0
	)
	var saved_profile_revision: int = (
		int(config.get_value(meta_section, "profile_content_revision", 0))
		if has_saved_data
		else -1
	)
	var saved_native_ids: Array = []
	if has_saved_data:
		var raw_saved_native = config.get_value(
			meta_section,
			"profile_native_ids",
			PackedStringArray()
		)
		if raw_saved_native is PackedStringArray or raw_saved_native is Array:
			for raw_id in raw_saved_native:
				saved_native_ids.append(StringName(str(raw_id)))

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

		# Development-safe authored-content migration. New native cards are merged
		# into an existing NPC collection without deleting cards won from the
		# player. Preferred deck ordering is refreshed, while priority/stolen cards
		# still remain hard constraints during the next rematch.
		if saved_profile_revision < _profile_content_revision:
			_merge_profile_content(saved_native_ids)
	else:
		_seed_initial_collection()

	_sanitize()
	_save()


func get_opponent_id() -> StringName:
	return _opponent_id


func build_match_deck(
	hand_size: int = HAND_SIZE,
	budget: int = 30,
	evolution_snapshot: Dictionary = {}
) -> Array:
	_budget = maxi(5, budget)
	var target_size: int = maxi(1, hand_size)
	_last_evolution_snapshot = evolution_snapshot.duplicate(true)
	_trim_priority_ids()

	var evolution_forced_ids: Array = []
	var raw_forced = evolution_snapshot.get(
		"forced_card_ids",
		PackedStringArray()
	)
	if raw_forced is PackedStringArray or raw_forced is Array:
		for raw_id in raw_forced:
			var card_id := StringName(str(raw_id))
			if not evolution_forced_ids.has(card_id):
				evolution_forced_ids.append(card_id)

	var ordered_ids: Array = []
	# Cards won from the player are ordered first. They are hard constraints for
	# the next rematch (up to the hand size), so a player never loses access to a
	# stolen card merely because an NPC's normal budget is temporarily too low.
	_append_unique_ids(ordered_ids, _priority_ids)
	_append_unique_ids(ordered_ids, evolution_forced_ids)
	_append_unique_ids(ordered_ids, _preferred_deck_ids)
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

	var ordered_cards: Array = []
	for raw_id in ordered_ids:
		var card = _card_for_id(StringName(raw_id))
		if card == null or not owns_card(card):
			continue
		if _contains_card_id(ordered_cards, StringName(card.card_id)):
			continue
		ordered_cards.append(card)

	var forced_cards: Array = []
	_append_forced_owned_cards(
		forced_cards,
		_priority_ids,
		target_size
	)
	# Stolen/recoverable cards remain the absolute first constraint. Evolution
	# cards fill only remaining forced slots and never hide a stolen card.
	_append_forced_owned_cards(
		forced_cards,
		evolution_forced_ids,
		target_size
	)

	var remaining_cards: Array = []
	for card in ordered_cards:
		if card != null and not _contains_card_id(
			forced_cards,
			StringName(card.card_id)
		):
			remaining_cards.append(card)

	var forced_cost: int = 0
	for card in forced_cards:
		forced_cost += maxi(0, int(card.deck_cost))

	var cards_needed: int = target_size - forced_cards.size()
	var effective_budget: int = _budget
	if cards_needed > 0:
		var cheapest_costs: Array[int] = []
		for card in remaining_cards:
			if card != null:
				cheapest_costs.append(maxi(0, int(card.deck_cost)))
		cheapest_costs.sort()
		if cheapest_costs.size() < cards_needed:
			push_warning(
				"TripleTriadOpponentCollection: %s does not own enough unique cards for a %d-card deck."
				% [String(_opponent_id), target_size]
			)
			return []
		var minimum_required_budget: int = forced_cost
		for index in range(cards_needed):
			minimum_required_budget += cheapest_costs[index]
		effective_budget = maxi(_budget, minimum_required_budget)
	else:
		effective_budget = maxi(_budget, forced_cost)

	var result: Array = forced_cards.duplicate()
	if cards_needed > 0:
		var filler: Array = _find_legal_deck(
			remaining_cards,
			cards_needed,
			maxi(0, effective_budget - forced_cost)
		)
		if filler.size() != cards_needed:
			push_warning(
				"TripleTriadOpponentCollection: %s has no legal %d-card deck under effective budget %d."
				% [String(_opponent_id), target_size, effective_budget]
			)
			return []
		result.append_array(filler)

	if result.size() != target_size:
		return []
	if effective_budget > _budget and not forced_cards.is_empty():
		push_warning(
			"TripleTriadOpponentCollection: %s temporarily raises deck budget %d -> %d so stolen cards remain recoverable."
			% [String(_opponent_id), _budget, effective_budget]
		)

	_deck_ids.clear()
	for card in result:
		_deck_ids.append(StringName(card.card_id))
	_trim_priority_ids()
	_save()
	return result

func acquire_card(card, make_priority: bool = true, save_now: bool = true) -> int:
	if card == null:
		return 0
	var card_id := StringName(card.card_id)
	var new_quantity: int = get_quantity_by_id(card_id) + 1
	_quantities[card_id] = new_quantity
	if make_priority:
		promote_card(card_id, false)
	if save_now:
		_save()
	return new_quantity


func remove_card(card, save_now: bool = true) -> int:
	if card == null:
		return 0
	return set_quantity_by_id(
		StringName(card.card_id),
		get_quantity_by_id(StringName(card.card_id)) - 1,
		save_now
	)


func set_quantity_by_id(card_id: StringName, quantity: int, save_now: bool = true) -> int:
	var clean_quantity: int = maxi(0, quantity)
	if clean_quantity <= 0:
		_quantities.erase(card_id)
		_deck_ids.erase(card_id)
		_priority_ids.erase(card_id)
	else:
		_quantities[card_id] = clean_quantity
	if save_now:
		_save()
	return clean_quantity


func promote_card(card_id: StringName, save_now: bool = true) -> void:
	if get_quantity_by_id(card_id) <= 0:
		return
	_priority_ids.erase(card_id)
	_priority_ids.push_front(card_id)
	_deck_ids.erase(card_id)
	_deck_ids.push_front(card_id)
	while _deck_ids.size() > HAND_SIZE:
		_deck_ids.pop_back()
	if save_now:
		_save()


func save_state() -> Error:
	return _save()


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


func get_deck_ids() -> PackedStringArray:
	return _to_packed_string_array(_deck_ids)


func get_priority_ids() -> PackedStringArray:
	return _to_packed_string_array(_priority_ids)


func get_quantities_snapshot() -> Dictionary:
	return _quantities.duplicate(true)


func get_runtime_snapshot() -> Dictionary:
	return {
		"opponent_id": String(_opponent_id),
		"deck_ids": get_deck_ids(),
		"priority_ids": get_priority_ids(),
		"quantities": get_quantities_snapshot(),
		"budget": _budget,
		"min_level": _min_level,
		"max_level": _max_level,
		"evolution": _last_evolution_snapshot.duplicate(true),
	}


func _append_forced_owned_cards(
	result: Array,
	card_ids,
	target_size: int
) -> void:
	if not (card_ids is PackedStringArray or card_ids is Array):
		return
	for raw_id in card_ids:
		if result.size() >= target_size:
			return
		var card = _card_for_id(StringName(str(raw_id)))
		if card == null or not owns_card(card):
			continue
		if _contains_card_id(result, StringName(card.card_id)):
			continue
		result.append(card)


func _read_profile_data() -> void:
	if _profile == null:
		return
	var revision_value = _profile.get("content_revision")
	if revision_value != null:
		_profile_content_revision = maxi(0, int(revision_value))
	var initial_size_value = _profile.get("initial_collection_size")
	if initial_size_value != null:
		_initial_collection_size = maxi(HAND_SIZE, int(initial_size_value))
	var raw_native = _profile.get("native_card_ids")
	if raw_native is PackedStringArray or raw_native is Array:
		for raw_id in raw_native:
			var card_id := StringName(str(raw_id))
			if not String(card_id).is_empty() and not _native_card_ids.has(card_id):
				_native_card_ids.append(card_id)
	var raw_preferred = _profile.get("preferred_deck_ids")
	if raw_preferred is PackedStringArray or raw_preferred is Array:
		for raw_id in raw_preferred:
			var card_id := StringName(str(raw_id))
			if not String(card_id).is_empty() and not _preferred_deck_ids.has(card_id):
				_preferred_deck_ids.append(card_id)



func _merge_profile_content(previous_native_ids: Array) -> void:
	if _catalog == null:
		return

	# Only grant cards that are genuinely new to this authored profile revision.
	# This is important after V1: if the player already won an older native card,
	# a later content revision must not silently recreate a second NPC copy. Old
	# prototype saves have no stored baseline, so revision 0 -> 1 intentionally
	# treats the full authored native set as newly introduced content.
	for raw_id in _native_card_ids:
		var card_id := StringName(raw_id)
		if previous_native_ids.has(card_id):
			continue
		var authored_card = _card_for_id(card_id)
		if authored_card != null and get_quantity_by_id(card_id) <= 0:
			_quantities[card_id] = 1

	# Refresh the baseline ordering using cards the NPC still owns. Stolen/priority
	# cards are never removed and build_match_deck() keeps them ahead of this list.
	_deck_ids.clear()
	for raw_id in _preferred_deck_ids:
		var card_id := StringName(raw_id)
		if get_quantity_by_id(card_id) > 0 and not _deck_ids.has(card_id):
			_deck_ids.append(card_id)
	_trim_priority_ids()


func _seed_initial_collection() -> void:
	_quantities.clear()
	_deck_ids.clear()
	_priority_ids.clear()
	if _catalog == null:
		return

	# Authored native cards are deterministic and always attempted first.
	for raw_id in _native_card_ids:
		var card_id := StringName(raw_id)
		var authored_card = _card_for_id(card_id)
		if authored_card != null:
			_quantities[card_id] = 1

	# Empty/unfilled authored pools keep the old prototype behavior, but the seed
	# remains stable for this opponent id across saves and sessions.
	if _catalog.has_method("get_cards_for_level_range") and _quantities.size() < _initial_collection_size:
		var candidates: Array = _catalog.call("get_cards_for_level_range", _min_level, _max_level)
		candidates.sort_custom(func(card_a, card_b):
			return _stable_seed_value(card_a) < _stable_seed_value(card_b)
		)
		for card in candidates:
			if _quantities.size() >= _initial_collection_size:
				break
			if card == null:
				continue
			var card_id := StringName(card.card_id)
			if not _quantities.has(card_id):
				_quantities[card_id] = 1

	# Keep only preferred cards that are actually owned. The legal solver below
	# fills the remaining slots without breaking the opponent budget.
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

	var clean_preferred: Array = []
	for raw_id in _preferred_deck_ids:
		var card_id := StringName(raw_id)
		if get_quantity_by_id(card_id) > 0 and _card_for_id(card_id) != null and not clean_preferred.has(card_id):
			clean_preferred.append(card_id)
	_preferred_deck_ids = clean_preferred
	_trim_priority_ids()


func _trim_priority_ids() -> void:
	var clean_priority: Array = []
	for raw_id in _priority_ids:
		var card_id := StringName(raw_id)
		if get_quantity_by_id(card_id) > 0 and _card_for_id(card_id) != null and not clean_priority.has(card_id):
			clean_priority.append(card_id)
	_priority_ids = clean_priority


func _find_legal_deck(
	cards: Array,
	target_size: int,
	budget: int
) -> Array:
	var memo: Dictionary = {}
	var result = _find_legal_deck_suffix(
		cards,
		0,
		maxi(0, target_size),
		maxi(0, budget),
		memo
	)
	return result if result is Array else []


func _find_legal_deck_suffix(
	cards: Array,
	index: int,
	cards_needed: int,
	budget_left: int,
	memo: Dictionary
):
	if cards_needed <= 0:
		return []
	if index >= cards.size():
		return null
	if cards.size() - index < cards_needed:
		return null

	var memo_key: String = "%d:%d:%d" % [index, cards_needed, budget_left]
	if memo.has(memo_key):
		var cached = memo[memo_key]
		if cached is Array:
			return cached.duplicate()
		return null

	var card = cards[index]
	if card != null:
		var card_cost: int = maxi(0, int(card.deck_cost))
		if card_cost <= budget_left:
			var suffix = _find_legal_deck_suffix(
				cards,
				index + 1,
				cards_needed - 1,
				budget_left - card_cost,
				memo
			)
			if suffix is Array:
				var with_card: Array = [card]
				with_card.append_array(suffix)
				memo[memo_key] = with_card.duplicate()
				return with_card

	var without_card = _find_legal_deck_suffix(
		cards,
		index + 1,
		cards_needed,
		budget_left,
		memo
	)
	if without_card is Array:
		memo[memo_key] = without_card.duplicate()
	else:
		memo[memo_key] = null
	return without_card


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


func _save() -> Error:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)

	var meta_section: String = _meta_section()
	var cards_section: String = _cards_section()
	if config.has_section(meta_section):
		config.erase_section(meta_section)
	if config.has_section(cards_section):
		config.erase_section(cards_section)

	config.set_value(meta_section, "version", SAVE_VERSION)
	config.set_value(meta_section, "profile_content_revision", _profile_content_revision)
	config.set_value(meta_section, "profile_native_ids", _to_packed_string_array(_native_card_ids))
	config.set_value(meta_section, "deck_ids", _to_packed_string_array(_deck_ids))
	config.set_value(meta_section, "priority_ids", _to_packed_string_array(_priority_ids))

	for raw_id in _quantities.keys():
		var card_id := StringName(raw_id)
		var quantity: int = maxi(0, int(_quantities[card_id]))
		if quantity > 0:
			config.set_value(cards_section, String(card_id), quantity)

	var save_error: Error = Storage.commit(config, SAVE_PATH)
	if save_error != OK:
		push_warning("TripleTriadOpponentCollection: could not save NPC cards (%s)." % error_string(save_error))
	return save_error


func _to_packed_string_array(values: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for value in values:
		result.append(String(value))
	return result
