extends RefCounted

const Storage = preload("res://scripts/triple_triad/triple_triad_config_store.gd")

const SAVE_PATH := "user://triple_triad_acquisition_history.cfg"
const SAVE_VERSION := 1

var _catalog: Resource = null
var _history: Dictionary = {}
var _event_count: int = 0


func initialize(catalog: Resource) -> void:
	_catalog = catalog
	_history.clear()
	_event_count = 0

	var config := ConfigFile.new()
	var load_error: Error = config.load(SAVE_PATH)
	if load_error == OK:
		_load_from_config(config)
		_sanitize_memory()
	elif load_error != ERR_FILE_NOT_FOUND:
		push_warning(
			"TripleTriadAcquisitionTracker: history save could not be loaded (%s)."
			% error_string(load_error)
		)
	_save()


func record_acquisition(
	card,
	source: StringName,
	opponent_id: StringName = &"",
	amount: int = 1
) -> void:
	if card == null or amount <= 0:
		return
	_record_event(
		StringName(card.card_id),
		source,
		opponent_id,
		maxi(1, amount),
		true
	)


func record_loss(
	card,
	source: StringName,
	opponent_id: StringName = &"",
	amount: int = 1
) -> void:
	if card == null or amount <= 0:
		return
	_record_event(
		StringName(card.card_id),
		source,
		opponent_id,
		maxi(1, amount),
		false
	)


func reconcile_card_history(
	card_id: StringName,
	desired_acquired: int,
	desired_lost: int,
	source: StringName,
	opponent_id: StringName = &""
) -> bool:
	var key: String = String(card_id).strip_edges()
	if key.is_empty():
		return false
	if (
		_catalog != null
		and _catalog.has_method("get_card_by_id")
		and _catalog.call("get_card_by_id", card_id) == null
	):
		return false

	var entry: Dictionary = _history.get(key, {
		"acquired": 0,
		"lost": 0,
		"first_source": "",
		"last_source": "",
		"last_opponent_id": "",
		"last_event_unix": 0,
	}).duplicate(true)

	var clean_acquired: int = maxi(0, desired_acquired)
	var clean_lost: int = maxi(0, desired_lost)
	var changed: bool = (
		int(entry.get("acquired", 0)) != clean_acquired
		or int(entry.get("lost", 0)) != clean_lost
	)
	if not changed:
		return _save() == OK

	entry["acquired"] = clean_acquired
	entry["lost"] = clean_lost
	if str(entry.get("first_source", "")).is_empty():
		entry["first_source"] = String(source)
	entry["last_source"] = String(source)
	entry["last_opponent_id"] = String(opponent_id)
	entry["last_event_unix"] = int(Time.get_unix_time_from_system())
	_history[key] = entry
	_event_count += 1
	return _save() == OK


func get_card_history(card_id: StringName) -> Dictionary:
	var key: String = String(card_id)
	if not _history.has(key):
		return {}
	var entry: Dictionary = _history[key]
	return entry.duplicate(true)


func get_all_history() -> Dictionary:
	return _history.duplicate(true)


func get_event_count() -> int:
	return _event_count


func save_state() -> Error:
	return _save()


func _record_event(
	card_id: StringName,
	source: StringName,
	opponent_id: StringName,
	amount: int,
	is_acquisition: bool
) -> void:
	var key: String = String(card_id).strip_edges()
	if key.is_empty():
		return

	var entry: Dictionary = _history.get(key, {
		"acquired": 0,
		"lost": 0,
		"first_source": "",
		"last_source": "",
		"last_opponent_id": "",
		"last_event_unix": 0,
	}).duplicate(true)

	if is_acquisition:
		entry["acquired"] = maxi(0, int(entry.get("acquired", 0))) + amount
	else:
		entry["lost"] = maxi(0, int(entry.get("lost", 0))) + amount

	if str(entry.get("first_source", "")).is_empty():
		entry["first_source"] = String(source)
	entry["last_source"] = String(source)
	entry["last_opponent_id"] = String(opponent_id)
	entry["last_event_unix"] = int(Time.get_unix_time_from_system())
	_history[key] = entry
	_event_count += 1
	_save()


func _load_from_config(config: ConfigFile) -> void:
	_event_count = maxi(0, int(config.get_value("meta", "event_count", 0)))
	for raw_section in config.get_sections():
		var section: String = str(raw_section)
		if not section.begins_with("card_"):
			continue
		var card_id: String = section.trim_prefix("card_")
		if card_id.is_empty():
			continue
		_history[card_id] = {
			"acquired": maxi(0, int(config.get_value(section, "acquired", 0))),
			"lost": maxi(0, int(config.get_value(section, "lost", 0))),
			"first_source": str(config.get_value(section, "first_source", "")),
			"last_source": str(config.get_value(section, "last_source", "")),
			"last_opponent_id": str(config.get_value(section, "last_opponent_id", "")),
			"last_event_unix": maxi(0, int(config.get_value(section, "last_event_unix", 0))),
		}


func _sanitize_memory() -> void:
	if _catalog == null or not _catalog.has_method("get_card_by_id"):
		return
	var invalid_ids: Array[String] = []
	for raw_id in _history.keys():
		var card_id: String = str(raw_id)
		if _catalog.call("get_card_by_id", StringName(card_id)) == null:
			invalid_ids.append(card_id)
	for card_id in invalid_ids:
		_history.erase(card_id)


func _save() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("meta", "event_count", maxi(0, _event_count))

	for raw_id in _history.keys():
		var card_id: String = str(raw_id)
		var entry: Dictionary = _history[raw_id]
		var section: String = _card_section(StringName(card_id))
		config.set_value(section, "acquired", maxi(0, int(entry.get("acquired", 0))))
		config.set_value(section, "lost", maxi(0, int(entry.get("lost", 0))))
		config.set_value(section, "first_source", str(entry.get("first_source", "")))
		config.set_value(section, "last_source", str(entry.get("last_source", "")))
		config.set_value(section, "last_opponent_id", str(entry.get("last_opponent_id", "")))
		config.set_value(section, "last_event_unix", maxi(0, int(entry.get("last_event_unix", 0))))

	var save_error: Error = Storage.commit(config, SAVE_PATH)
	if save_error != OK:
		push_warning(
			"TripleTriadAcquisitionTracker: could not save history (%s)."
			% error_string(save_error)
		)
	return save_error


func _card_section(card_id: StringName) -> String:
	return "card_%s" % String(card_id)
