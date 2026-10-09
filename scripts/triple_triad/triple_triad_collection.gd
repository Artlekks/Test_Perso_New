extends RefCounted

const SAVE_PATH := "user://triple_triad_collection.cfg"
const SAVE_VERSION := 3
const Storage = preload("res://scripts/triple_triad/triple_triad_config_store.gd")

var _catalog: Resource = null
var _quantities: Dictionary = {}
var _acquisition_policy: Resource = null
var _load_error: Error = OK
var _committed_hash := ""


func initialize(catalog: Resource, acquisition_policy: Resource = null) -> void:
	_catalog = catalog
	_acquisition_policy = acquisition_policy
	_quantities.clear()
	_committed_hash = ""

	var config := ConfigFile.new()
	_load_error = Storage.load_recover(config, SAVE_PATH)
	if _load_error == ERR_FILE_NOT_FOUND:
		_load_error = OK
		_seed_new_collection()
		_save()
		return
	if _load_error != OK:
		push_warning("TripleTriadCollection: unreadable save retained; ownership writes disabled.")
		return
	_committed_hash = FileAccess.get_sha256(SAVE_PATH)

	var stored_version: int = int(config.get_value("meta", "version", 0))
	if stored_version > SAVE_VERSION:
		_load_error = ERR_INVALID_DATA
		push_warning("TripleTriadCollection: newer save retained; ownership writes disabled.")
		return
	if stored_version <= 0:
		_load_error = ERR_INVALID_DATA
		push_warning("TripleTriadCollection: invalid version retained; ownership writes disabled.")
		return

	if config.has_section("cards"):
		for raw_key in config.get_section_keys("cards"):
			if not config.get_value("cards", raw_key) is int:
				_load_error = ERR_INVALID_DATA
				_quantities.clear()
				push_warning("TripleTriadCollection: invalid quantity retained; ownership writes disabled.")
				return
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
	return set_quantity_by_id(card_id, new_quantity, save_now)


func remove_card(card, amount: int = 1, save_now: bool = true) -> int:
	if card == null or amount <= 0:
		return 0
	var card_id := StringName(card.card_id)
	var current_quantity: int = get_quantity_by_id(card_id)
	var new_quantity: int = maxi(0, current_quantity - amount)
	return set_quantity_by_id(card_id, new_quantity, save_now)


func set_quantity_by_id(card_id: StringName, quantity: int, save_now: bool = true) -> int:
	var previous: int = get_quantity_by_id(card_id)
	if _load_error != OK or _catalog == null or _catalog.call("get_card_by_id", card_id) == null:
		return previous
	var clean_quantity: int = maxi(0, quantity)
	if not _duplicates_allowed():
		clean_quantity = mini(clean_quantity, 1)
	if clean_quantity <= 0:
		_quantities.erase(card_id)
	else:
		_quantities[card_id] = clean_quantity
	if save_now and _save() != OK:
		if previous > 0:
			_quantities[card_id] = previous
		else:
			_quantities.erase(card_id)
		return previous
	return clean_quantity


func save_state() -> Error:
	return _save()


func can_commit_state() -> Error:
	if _load_error != OK:
		return _load_error
	var disk_hash: String = FileAccess.get_sha256(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	return OK if disk_hash == _committed_hash else ERR_BUSY


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


func restore_quantities_snapshot(snapshot: Dictionary) -> Error:
	# Transaction rollback only; never UI/match-owned storage.
	for raw_id in snapshot:
		if not (raw_id is String or raw_id is StringName) or not snapshot[raw_id] is int or int(snapshot[raw_id]) < 0:
			return ERR_INVALID_DATA
	_quantities = snapshot.duplicate(true)
	_sanitize_against_catalog()
	return OK


func _duplicates_allowed() -> bool:
	if _acquisition_policy == null:
		return true
	var value = _acquisition_policy.get("allow_duplicate_ownership")
	return true if value == null else bool(value)


func _save() -> Error:
	var commit_error: Error = can_commit_state()
	if commit_error != OK:
		push_warning("TripleTriadCollection: stale/unreadable owner cannot overwrite the canonical save.")
		return commit_error
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	for raw_id in _quantities.keys():
		var card_id := StringName(raw_id)
		var quantity: int = maxi(0, int(_quantities[card_id]))
		if quantity > 0:
			config.set_value("cards", String(card_id), quantity)

	var save_error: Error = Storage.commit(config, SAVE_PATH)
	if save_error == OK:
		_committed_hash = FileAccess.get_sha256(SAVE_PATH)
	if save_error != OK:
		push_warning("TripleTriadCollection: could not save collection (%s)." % error_string(save_error))
	return save_error
