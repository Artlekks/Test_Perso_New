extends RefCounted

const SAVE_PATH := "user://triple_triad_encounter_records.cfg"
const SAVE_VERSION := 1

const RESULT_NONE := "none"
const RESULT_WIN := "win"
const RESULT_LOSS := "loss"
const RESULT_DRAW := "draw"

var _records: Dictionary = {}
var _stolen: Dictionary = {}


func initialize() -> void:
	_records.clear()
	_stolen.clear()
	var config := ConfigFile.new()
	var load_error: Error = config.load(SAVE_PATH)
	if load_error == OK:
		_load_from_config(config)
		_sanitize_memory()
	elif load_error != ERR_FILE_NOT_FOUND:
		push_warning(
			"TripleTriadEncounterRecords: records save could not be loaded (%s)."
			% error_string(load_error)
		)
	_save()


func record_result(
	opponent_id: StringName,
	winner: int,
	player_owner: int,
	opponent_owner: int
) -> Dictionary:
	var key: String = _clean_key(opponent_id)
	if key.is_empty():
		return {}

	var record: Dictionary = _records.get(key, _new_record()).duplicate(true)
	record["matches"] = maxi(0, int(record.get("matches", 0))) + 1
	var result: String = RESULT_DRAW
	if winner == player_owner:
		record["wins"] = maxi(0, int(record.get("wins", 0))) + 1
		result = RESULT_WIN
	elif winner == opponent_owner:
		record["losses"] = maxi(0, int(record.get("losses", 0))) + 1
		result = RESULT_LOSS
	else:
		record["draws"] = maxi(0, int(record.get("draws", 0))) + 1

	var now: int = int(Time.get_unix_time_from_system())
	record["last_result"] = result
	record["last_played_unix"] = now
	if result == RESULT_WIN and int(record.get("first_win_unix", 0)) <= 0:
		record["first_win_unix"] = now
	_records[key] = record
	_save()
	return get_snapshot(StringName(key))


func record_card_stolen(
	opponent_id: StringName,
	card_id: StringName,
	amount: int = 1
) -> Dictionary:
	var opponent_key: String = _clean_key(opponent_id)
	var card_key: String = _clean_key(card_id)
	if opponent_key.is_empty() or card_key.is_empty() or amount <= 0:
		return {}

	var add_amount: int = maxi(1, amount)
	var record: Dictionary = _records.get(opponent_key, _new_record()).duplicate(true)
	record["cards_lost_to_opponent"] = (
		maxi(0, int(record.get("cards_lost_to_opponent", 0))) + add_amount
	)
	_records[opponent_key] = record

	var stolen_for_opponent: Dictionary = _stolen.get(opponent_key, {}).duplicate(true)
	stolen_for_opponent[card_key] = maxi(0, int(stolen_for_opponent.get(card_key, 0))) + add_amount
	_stolen[opponent_key] = stolen_for_opponent
	_save()
	return get_snapshot(StringName(opponent_key))


func record_card_recovered(
	opponent_id: StringName,
	card_id: StringName,
	amount: int = 1
) -> Dictionary:
	var opponent_key: String = _clean_key(opponent_id)
	var card_key: String = _clean_key(card_id)
	if opponent_key.is_empty() or card_key.is_empty() or amount <= 0:
		return {}

	var won_amount: int = maxi(1, amount)
	var stolen_for_opponent: Dictionary = _stolen.get(opponent_key, {}).duplicate(true)
	var current: int = maxi(0, int(stolen_for_opponent.get(card_key, 0)))
	var recovered_stolen: int = mini(current, won_amount)
	var remaining: int = maxi(0, current - recovered_stolen)
	if remaining <= 0:
		stolen_for_opponent.erase(card_key)
	else:
		stolen_for_opponent[card_key] = remaining
	if stolen_for_opponent.is_empty():
		_stolen.erase(opponent_key)
	else:
		_stolen[opponent_key] = stolen_for_opponent

	var record: Dictionary = _records.get(opponent_key, _new_record()).duplicate(true)
	record["cards_won_from_opponent"] = (
		maxi(0, int(record.get("cards_won_from_opponent", 0))) + won_amount
	)
	if recovered_stolen > 0:
		record["stolen_cards_recovered"] = (
			maxi(0, int(record.get("stolen_cards_recovered", 0))) + recovered_stolen
		)
	_records[opponent_key] = record
	_save()
	return get_snapshot(StringName(opponent_key))


func get_snapshot(opponent_id: StringName) -> Dictionary:
	var key: String = _clean_key(opponent_id)
	if key.is_empty():
		return _empty_snapshot(&"")

	var record: Dictionary = _records.get(key, _new_record()).duplicate(true)
	var stolen_quantities: Dictionary = _stolen.get(key, {}).duplicate(true)
	var stolen_total: int = 0
	for raw_quantity in stolen_quantities.values():
		stolen_total += maxi(0, int(raw_quantity))

	return {
		"opponent_id": key,
		"matches": maxi(0, int(record.get("matches", 0))),
		"wins": maxi(0, int(record.get("wins", 0))),
		"losses": maxi(0, int(record.get("losses", 0))),
		"draws": maxi(0, int(record.get("draws", 0))),
		"beaten_before": int(record.get("wins", 0)) > 0,
		"first_win_unix": maxi(0, int(record.get("first_win_unix", 0))),
		"last_result": str(record.get("last_result", RESULT_NONE)),
		"last_played_unix": maxi(0, int(record.get("last_played_unix", 0))),
		"cards_won_from_opponent": maxi(0, int(record.get("cards_won_from_opponent", 0))),
		"cards_lost_to_opponent": maxi(0, int(record.get("cards_lost_to_opponent", 0))),
		"stolen_cards_recovered": maxi(0, int(record.get("stolen_cards_recovered", 0))),
		"stolen_quantities": stolen_quantities,
		"stolen_total": stolen_total,
	}


func get_all_recorded_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for raw_id in _records.keys():
		result.append(str(raw_id))
	for raw_id in _stolen.keys():
		if not result.has(str(raw_id)):
			result.append(str(raw_id))
	result.sort()
	return result


func save_state() -> Error:
	return _save()


func _load_from_config(config: ConfigFile) -> void:
	for raw_section in config.get_sections():
		var section: String = str(raw_section)
		if section.begins_with("opponent_") and section.ends_with("_record"):
			var key: String = section.trim_prefix("opponent_").trim_suffix("_record")
			if key.is_empty():
				continue
			_records[key] = {
				"matches": maxi(0, int(config.get_value(section, "matches", 0))),
				"wins": maxi(0, int(config.get_value(section, "wins", 0))),
				"losses": maxi(0, int(config.get_value(section, "losses", 0))),
				"draws": maxi(0, int(config.get_value(section, "draws", 0))),
				"first_win_unix": maxi(0, int(config.get_value(section, "first_win_unix", 0))),
				"last_result": str(config.get_value(section, "last_result", RESULT_NONE)),
				"last_played_unix": maxi(0, int(config.get_value(section, "last_played_unix", 0))),
				"cards_won_from_opponent": maxi(0, int(config.get_value(section, "cards_won_from_opponent", 0))),
				"cards_lost_to_opponent": maxi(0, int(config.get_value(section, "cards_lost_to_opponent", 0))),
				"stolen_cards_recovered": maxi(0, int(config.get_value(section, "stolen_cards_recovered", 0))),
			}
		elif section.begins_with("opponent_") and section.ends_with("_stolen"):
			var key: String = section.trim_prefix("opponent_").trim_suffix("_stolen")
			if key.is_empty():
				continue
			var entries: Dictionary = {}
			for raw_card_id in config.get_section_keys(section):
				var quantity: int = maxi(0, int(config.get_value(section, raw_card_id, 0)))
				if quantity > 0:
					entries[str(raw_card_id)] = quantity
			if not entries.is_empty():
				_stolen[key] = entries


func _sanitize_memory() -> void:
	for raw_id in _records.keys():
		var key: String = str(raw_id)
		var record: Dictionary = _records[raw_id]
		var wins: int = maxi(0, int(record.get("wins", 0)))
		var losses: int = maxi(0, int(record.get("losses", 0)))
		var draws: int = maxi(0, int(record.get("draws", 0)))
		record["wins"] = wins
		record["losses"] = losses
		record["draws"] = draws
		record["matches"] = maxi(maxi(0, int(record.get("matches", 0))), wins + losses + draws)
		record["first_win_unix"] = maxi(0, int(record.get("first_win_unix", 0)))
		record["last_played_unix"] = maxi(0, int(record.get("last_played_unix", 0)))
		record["cards_won_from_opponent"] = maxi(0, int(record.get("cards_won_from_opponent", 0)))
		record["cards_lost_to_opponent"] = maxi(0, int(record.get("cards_lost_to_opponent", 0)))
		record["stolen_cards_recovered"] = maxi(0, int(record.get("stolen_cards_recovered", 0)))
		_records[key] = record

	for raw_id in _stolen.keys():
		var key: String = str(raw_id)
		var entries: Dictionary = _stolen[raw_id]
		var clean: Dictionary = {}
		for raw_card_id in entries.keys():
			var quantity: int = maxi(0, int(entries[raw_card_id]))
			if quantity > 0:
				clean[str(raw_card_id)] = quantity
		if clean.is_empty():
			_stolen.erase(raw_id)
		else:
			_stolen[key] = clean


func _new_record() -> Dictionary:
	return {
		"matches": 0,
		"wins": 0,
		"losses": 0,
		"draws": 0,
		"first_win_unix": 0,
		"last_result": RESULT_NONE,
		"last_played_unix": 0,
		"cards_won_from_opponent": 0,
		"cards_lost_to_opponent": 0,
		"stolen_cards_recovered": 0,
	}


func _empty_snapshot(opponent_id: StringName) -> Dictionary:
	var result: Dictionary = _new_record()
	result["opponent_id"] = String(opponent_id)
	result["beaten_before"] = false
	result["stolen_quantities"] = {}
	result["stolen_total"] = 0
	return result


func _save() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	for raw_id in _records.keys():
		var key: String = str(raw_id)
		var section: String = _record_section(StringName(key))
		var record: Dictionary = _records[raw_id]
		for field in [
			"matches", "wins", "losses", "draws", "first_win_unix",
			"last_result", "last_played_unix", "cards_won_from_opponent",
			"cards_lost_to_opponent", "stolen_cards_recovered",
		]:
			config.set_value(section, field, record.get(field, 0 if field != "last_result" else RESULT_NONE))

	for raw_id in _stolen.keys():
		var key: String = str(raw_id)
		var section: String = _stolen_section(StringName(key))
		var entries: Dictionary = _stolen[raw_id]
		for raw_card_id in entries.keys():
			var quantity: int = maxi(0, int(entries[raw_card_id]))
			if quantity > 0:
				config.set_value(section, str(raw_card_id), quantity)

	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning(
			"TripleTriadEncounterRecords: save failed (%s)."
			% error_string(save_error)
		)
	return save_error


func _record_section(opponent_id: StringName) -> String:
	return "opponent_%s_record" % String(opponent_id)


func _stolen_section(opponent_id: StringName) -> String:
	return "opponent_%s_stolen" % String(opponent_id)


func _clean_key(value: StringName) -> String:
	return String(value).strip_edges()
