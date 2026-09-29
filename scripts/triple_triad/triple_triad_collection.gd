extends RefCounted

const SAVE_PATH := "user://triple_triad_collection.cfg"
const SAVE_VERSION := 1

var _catalog: Resource = null
var _quantities: Dictionary = {}


func initialize(catalog: Resource) -> void:
	_catalog = catalog
	_quantities.clear()

	var config := ConfigFile.new()
	var load_error: Error = config.load(SAVE_PATH)
	if load_error != OK:
		_seed_full_collection()
		_save()
		return

	var stored_version: int = int(config.get_value("meta", "version", 0))
	if stored_version <= 0:
		_seed_full_collection()
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


func acquire_card(card, amount: int = 1) -> int:
	if card == null or amount <= 0:
		return 0
	var card_id := StringName(card.card_id)
	var new_quantity: int = get_quantity_by_id(card_id) + amount
	_quantities[card_id] = new_quantity
	_save()
	return new_quantity


func remove_card(card, amount: int = 1) -> int:
	if card == null or amount <= 0:
		return 0
	var card_id := StringName(card.card_id)
	var current_quantity: int = get_quantity_by_id(card_id)
	var new_quantity: int = maxi(0, current_quantity - amount)
	if new_quantity <= 0:
		_quantities.erase(card_id)
	else:
		_quantities[card_id] = new_quantity
	_save()
	return new_quantity


func unique_owned_count() -> int:
	return _quantities.size()


func total_owned_count() -> int:
	var total: int = 0
	for raw_quantity in _quantities.values():
		total += maxi(0, int(raw_quantity))
	return total


func _seed_full_collection() -> void:
	_quantities.clear()
	if _catalog == null or not _catalog.has_method("get_total_source_count"):
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
	for card_id in invalid_ids:
		_quantities.erase(card_id)


func _save() -> void:
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
