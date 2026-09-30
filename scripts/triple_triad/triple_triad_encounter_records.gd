extends RefCounted

const SAVE_PATH := "user://triple_triad_encounter_records.cfg"
const SAVE_VERSION := 1

const RESULT_NONE := "none"
const RESULT_WIN := "win"
const RESULT_LOSS := "loss"
const RESULT_DRAW := "draw"


func initialize() -> void:
	var config := ConfigFile.new()
	var load_error: Error = config.load(SAVE_PATH)
	if load_error != OK:
		config.set_value("meta", "version", SAVE_VERSION)
		config.save(SAVE_PATH)
		return

	_sanitize(config)
	config.set_value("meta", "version", SAVE_VERSION)
	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning(
			"TripleTriadEncounterRecords: could not save repaired records (%s)."
			% error_string(save_error)
		)


func record_result(
	opponent_id: StringName,
	winner: int,
	player_owner: int,
	opponent_owner: int
) -> Dictionary:
	var clean_id: StringName = _clean_id(opponent_id)
	if clean_id == &"":
		return {}

	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	var section: String = _record_section(clean_id)

	var matches: int = maxi(0, int(config.get_value(section, "matches", 0))) + 1
	var wins: int = maxi(0, int(config.get_value(section, "wins", 0)))
	var losses: int = maxi(0, int(config.get_value(section, "losses", 0)))
	var draws: int = maxi(0, int(config.get_value(section, "draws", 0)))
	var result: String = RESULT_DRAW

	if winner == player_owner:
		wins += 1
		result = RESULT_WIN
	elif winner == opponent_owner:
		losses += 1
		result = RESULT_LOSS
	else:
		draws += 1

	var now: int = int(Time.get_unix_time_from_system())
	config.set_value(section, "matches", matches)
	config.set_value(section, "wins", wins)
	config.set_value(section, "losses", losses)
	config.set_value(section, "draws", draws)
	config.set_value(section, "last_result", result)
	config.set_value(section, "last_played_unix", now)

	if result == RESULT_WIN and int(config.get_value(section, "first_win_unix", 0)) <= 0:
		config.set_value(section, "first_win_unix", now)

	config.set_value("meta", "version", SAVE_VERSION)
	_save_config(config)
	return get_snapshot(clean_id)


func record_card_stolen(
	opponent_id: StringName,
	card_id: StringName,
	amount: int = 1
) -> Dictionary:
	var clean_opponent: StringName = _clean_id(opponent_id)
	var clean_card: StringName = _clean_id(card_id)
	if clean_opponent == &"" or clean_card == &"" or amount <= 0:
		return {}

	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	var record_section: String = _record_section(clean_opponent)
	var stolen_section: String = _stolen_section(clean_opponent)
	var add_amount: int = maxi(1, amount)

	var current: int = maxi(
		0,
		int(config.get_value(stolen_section, String(clean_card), 0))
	)
	config.set_value(stolen_section, String(clean_card), current + add_amount)
	config.set_value(
		record_section,
		"cards_lost_to_opponent",
		maxi(0, int(config.get_value(record_section, "cards_lost_to_opponent", 0))) + add_amount
	)
	config.set_value("meta", "version", SAVE_VERSION)
	_save_config(config)
	return get_snapshot(clean_opponent)


func record_card_recovered(
	opponent_id: StringName,
	card_id: StringName,
	amount: int = 1
) -> Dictionary:
	var clean_opponent: StringName = _clean_id(opponent_id)
	var clean_card: StringName = _clean_id(card_id)
	if clean_opponent == &"" or clean_card == &"" or amount <= 0:
		return {}

	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	var record_section: String = _record_section(clean_opponent)
	var stolen_section: String = _stolen_section(clean_opponent)
	var won_amount: int = maxi(1, amount)

	var current: int = maxi(
		0,
		int(config.get_value(stolen_section, String(clean_card), 0))
	)
	var recovered_stolen: int = mini(current, won_amount)
	var remaining: int = maxi(0, current - recovered_stolen)

	if remaining <= 0:
		config.erase_section_key(stolen_section, String(clean_card))
	else:
		config.set_value(stolen_section, String(clean_card), remaining)

	config.set_value(
		record_section,
		"cards_won_from_opponent",
		maxi(0, int(config.get_value(record_section, "cards_won_from_opponent", 0))) + won_amount
	)
	if recovered_stolen > 0:
		config.set_value(
			record_section,
			"stolen_cards_recovered",
			maxi(0, int(config.get_value(record_section, "stolen_cards_recovered", 0))) + recovered_stolen
		)

	config.set_value("meta", "version", SAVE_VERSION)
	_save_config(config)
	return get_snapshot(clean_opponent)


func get_snapshot(opponent_id: StringName) -> Dictionary:
	var clean_id: StringName = _clean_id(opponent_id)
	if clean_id == &"":
		return _empty_snapshot(&"")

	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return _empty_snapshot(clean_id)

	var section: String = _record_section(clean_id)
	var wins: int = maxi(0, int(config.get_value(section, "wins", 0)))
	var losses: int = maxi(0, int(config.get_value(section, "losses", 0)))
	var draws: int = maxi(0, int(config.get_value(section, "draws", 0)))
	var matches: int = maxi(
		maxi(0, int(config.get_value(section, "matches", 0))),
		wins + losses + draws
	)

	var stolen_quantities: Dictionary = _read_stolen_quantities(config, clean_id)
	var stolen_total: int = 0
	for raw_quantity in stolen_quantities.values():
		stolen_total += maxi(0, int(raw_quantity))

	return {
		"opponent_id": String(clean_id),
		"matches": matches,
		"wins": wins,
		"losses": losses,
		"draws": draws,
		"beaten_before": wins > 0,
		"first_win_unix": maxi(0, int(config.get_value(section, "first_win_unix", 0))),
		"last_result": str(config.get_value(section, "last_result", RESULT_NONE)),
		"last_played_unix": maxi(0, int(config.get_value(section, "last_played_unix", 0))),
		"cards_won_from_opponent": maxi(0, int(config.get_value(section, "cards_won_from_opponent", 0))),
		"cards_lost_to_opponent": maxi(0, int(config.get_value(section, "cards_lost_to_opponent", 0))),
		"stolen_cards_recovered": maxi(0, int(config.get_value(section, "stolen_cards_recovered", 0))),
		"stolen_quantities": stolen_quantities,
		"stolen_total": stolen_total,
	}


func get_all_recorded_ids() -> PackedStringArray:
	var result := PackedStringArray()
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return result

	for raw_section in config.get_sections():
		var section: String = str(raw_section)
		if section.begins_with("opponent_") and section.ends_with("_record"):
			var opponent_id: String = section.trim_prefix("opponent_").trim_suffix("_record")
			if not opponent_id.is_empty():
				result.append(opponent_id)
	return result


func save_state() -> Error:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		config.set_value("meta", "version", SAVE_VERSION)
	return _save_config(config)


func _empty_snapshot(opponent_id: StringName) -> Dictionary:
	return {
		"opponent_id": String(opponent_id),
		"matches": 0,
		"wins": 0,
		"losses": 0,
		"draws": 0,
		"beaten_before": false,
		"first_win_unix": 0,
		"last_result": RESULT_NONE,
		"last_played_unix": 0,
		"cards_won_from_opponent": 0,
		"cards_lost_to_opponent": 0,
		"stolen_cards_recovered": 0,
		"stolen_quantities": {},
		"stolen_total": 0,
	}


func _read_stolen_quantities(
	config: ConfigFile,
	opponent_id: StringName
) -> Dictionary:
	var result: Dictionary = {}
	var section: String = _stolen_section(opponent_id)
	if not config.has_section(section):
		return result

	for raw_key in config.get_section_keys(section):
		var quantity: int = maxi(0, int(config.get_value(section, raw_key, 0)))
		if quantity > 0:
			result[str(raw_key)] = quantity
	return result


func _sanitize(config: ConfigFile) -> void:
	for raw_section in config.get_sections():
		var section: String = str(raw_section)
		if section.ends_with("_record"):
			for key in [
				"matches",
				"wins",
				"losses",
				"draws",
				"first_win_unix",
				"last_played_unix",
				"cards_won_from_opponent",
				"cards_lost_to_opponent",
				"stolen_cards_recovered",
			]:
				config.set_value(
					section,
					key,
					maxi(0, int(config.get_value(section, key, 0)))
				)

			var resolved: int = (
				int(config.get_value(section, "wins", 0))
				+ int(config.get_value(section, "losses", 0))
				+ int(config.get_value(section, "draws", 0))
			)
			if int(config.get_value(section, "matches", 0)) < resolved:
				config.set_value(section, "matches", resolved)

		elif section.ends_with("_stolen"):
			for raw_key in config.get_section_keys(section):
				var quantity: int = maxi(
					0,
					int(config.get_value(section, raw_key, 0))
				)
				if quantity <= 0:
					config.erase_section_key(section, str(raw_key))
				else:
					config.set_value(section, str(raw_key), quantity)


func _record_section(opponent_id: StringName) -> String:
	return "opponent_%s_record" % String(opponent_id)


func _stolen_section(opponent_id: StringName) -> String:
	return "opponent_%s_stolen" % String(opponent_id)


func _clean_id(value: StringName) -> StringName:
	var clean: String = String(value).strip_edges()
	return &"" if clean.is_empty() else StringName(clean)


func _save_config(config: ConfigFile) -> Error:
	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning(
			"TripleTriadEncounterRecords: save failed (%s)."
			% error_string(save_error)
		)
	return save_error
