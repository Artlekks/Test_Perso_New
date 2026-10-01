extends RefCounted

const SAVE_PATH := "user://triple_triad_collection.cfg"
const SAVE_VERSION := 3

var _catalog: Resource = null
var _quantities: Dictionary = {}
var _acquisition_policy: Resource = null


func initialize(catalog: Resource, acquisition_policy: Resource = null) -> void:
	_catalog = catalog
	_acquisition_policy = acquisition_policy
	_quantities.clear()

	var config := ConfigFile.new()
	var load_error: Error = config.load(SAVE_PATH)
	if load_error != OK:
		_seed_new_collection()
		_save()
		return

	var stored_version: int = int(config.get_value("meta", "version", 0))
	if stored_version <= 0:
		_seed_new_collection()
		_save()
		return

	if config.has_section("cards"):
		for raw_key in config.get_section_keys("cards"):
			var card_id := StringName(str(raw_key))
			var quantity: int = maxi(0, int(config.get_value("cards", raw_key, 0)))
			if quantity > 0:
				_quantities[card_id] = quantity

	_sanitize_against_catalog()
	_save()


func get_owned_cards() -> Array:
	var result: Array = []
	if _catalog == null or not _catalog.has_method("get_total_source_count"):
		return result

	for source_index in range(int(_catalog.call("get_total_source_count"))):
		var card = _catalog.call("get_card", source_index)
		if card != null and owns_card(card):
			result.append(card)
	return result


func owns_card(card) -> bool:
	if card == null:
		return false
	return get_quantity_by_id(StringName(card.card_id)) > 0


func get_quantity(card) -> int:
	if card == null:
		return 0
	return get_quantity_by_id(StringName(card.card_id))


func get_quantity_by_id(card_id: StringName) -> int:
	return maxi(0, int(_quantities.get(card_id, 0)))


func acquire_card(card, amount: int = 1, save_now: bool = true) -> int:
	if card == null or amount <= 0:
		return 0
	var card_id := StringName(card.card_id)
	var new_quantity: int = get_quantity_by_id(card_id) + amount
	if not _duplicates_allowed():
		new_quantity = mini(new_quantity, 1)
	_quantities[card_id] = new_quantity
	if save_now:
		_save()
	return new_quantity


func remove_card(card, amount: int = 1, save_now: bool = true) -> int:
	if card == null or amount <= 0:
		return 0
	var card_id := StringName(card.card_id)
	var current_quantity: int = get_quantity_by_id(card_id)
	var new_quantity: int = maxi(0, current_quantity - amount)
	if new_quantity <= 0:
		_quantities.erase(card_id)
	else:
		_quantities[card_id] = new_quantity
	if save_now:
		_save()
	return new_quantity


func set_quantity_by_id(card_id: StringName, quantity: int, save_now: bool = true) -> int:
	var clean_quantity: int = maxi(0, quantity)
	if not _duplicates_allowed():
		clean_quantity = mini(clean_quantity, 1)
	if clean_quantity <= 0:
		_quantities.erase(card_id)
	else:
		_quantities[card_id] = clean_quantity
	if save_now:
		_save()
	return clean_quantity


func save_state() -> Error:
	return _save()


func unique_owned_count() -> int:
	return _quantities.size()


func total_owned_count() -> int:
	var total: int = 0
	for raw_quantity in _quantities.values():
		total += maxi(0, int(raw_quantity))
	return total


func _seed_new_collection() -> void:
	_quantities.clear()
	if _catalog == null:
		return

	if _acquisition_policy != null:
		var auto_seed_value = _acquisition_policy.get("auto_seed_new_collection")
		var auto_seed: bool = bool(auto_seed_value) if auto_seed_value != null else true
		if (
			auto_seed
			and _acquisition_policy.has_method("build_starting_collection")
		):
			var starter_cards: Array = _acquisition_policy.call(
				"build_starting_collection",
				_catalog
			)
			for card in starter_cards:
				if card != null:
					_quantities[StringName(card.card_id)] = 1
		return

	# Compatibility fallback only for projects that intentionally omit an
	# acquisition policy entirely. TripleTriadGame supplies one by default.
	if not _catalog.has_method("get_total_source_count"):
		return
	for source_index in range(int(_catalog.call("get_total_source_count"))):
		var card = _catalog.call("get_card", source_index)
		if card != null:
			_quantities[StringName(card.card_id)] = 1


func _sanitize_against_catalog() -> void:
	if _catalog == null or not _catalog.has_method("get_card_by_id"):
		return
	var invalid_ids: Array = []
	for raw_id in _quantities.keys():
		var card_id := StringName(raw_id)
		if _catalog.call("get_card_by_id", card_id) == null:
			invalid_ids.append(card_id)
		elif not _duplicates_allowed() and int(_quantities[raw_id]) > 1:
			_quantities[raw_id] = 1
	for card_id in invalid_ids:
		_quantities.erase(card_id)


func get_quantities_snapshot() -> Dictionary:
	return _quantities.duplicate(true)


func _duplicates_allowed() -> bool:
	if _acquisition_policy == null:
		return true
	var value = _acquisition_policy.get("allow_duplicate_ownership")
	return true if value == null else bool(value)


func _save() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	for raw_id in _quantities.keys():
		var card_id := StringName(raw_id)
		var quantity: int = maxi(0, int(_quantities[card_id]))
		if quantity > 0:
			config.set_value("cards", String(card_id), quantity)

	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning("TripleTriadCollection: could not save collection (%s)." % error_string(save_error))
	return save_error
