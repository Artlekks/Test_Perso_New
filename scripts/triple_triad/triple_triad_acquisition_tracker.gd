extends RefCounted

const SAVE_PATH := "user://triple_triad_acquisition_history.cfg"
const SAVE_VERSION := 1

var _catalog: Resource = null


func initialize(catalog: Resource) -> void:
	_catalog = catalog
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		config.set_value("meta", "version", SAVE_VERSION)
		config.set_value("meta", "event_count", 0)
		config.save(SAVE_PATH)
		return
	_sanitize(config)
	config.save(SAVE_PATH)


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


func get_card_history(card_id: StringName) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return {}
	var section: String = _card_section(card_id)
	if not config.has_section(section):
		return {}
	return {
		"acquired": maxi(0, int(config.get_value(section, "acquired", 0))),
		"lost": maxi(0, int(config.get_value(section, "lost", 0))),
		"first_source": str(config.get_value(section, "first_source", "")),
		"last_source": str(config.get_value(section, "last_source", "")),
		"last_opponent_id": str(
			config.get_value(section, "last_opponent_id", "")
		),
		"last_event_unix": int(
			config.get_value(section, "last_event_unix", 0)
		),
	}


func get_event_count() -> int:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return 0
	return maxi(0, int(config.get_value("meta", "event_count", 0)))


func _record_event(
	card_id: StringName,
	source: StringName,
	opponent_id: StringName,
	amount: int,
	is_acquisition: bool
) -> void:
	if String(card_id).is_empty():
		return

	var config := ConfigFile.new()
	config.load(SAVE_PATH)

	var section: String = _card_section(card_id)
	var acquired: int = maxi(0, int(config.get_value(section, "acquired", 0)))
	var lost: int = maxi(0, int(config.get_value(section, "lost", 0)))

	if is_acquisition:
		acquired += amount
	else:
		lost += amount

	if str(config.get_value(section, "first_source", "")).is_empty():
		config.set_value(section, "first_source", String(source))
	config.set_value(section, "acquired", acquired)
	config.set_value(section, "lost", lost)
	config.set_value(section, "last_source", String(source))
	config.set_value(section, "last_opponent_id", String(opponent_id))
	config.set_value(
		section,
		"last_event_unix",
		int(Time.get_unix_time_from_system())
	)

	var event_count: int = maxi(
		0,
		int(config.get_value("meta", "event_count", 0))
	) + 1
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("meta", "event_count", event_count)

	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning(
			"TripleTriadAcquisitionTracker: could not save history (%s)."
			% error_string(save_error)
		)


func _sanitize(config: ConfigFile) -> void:
	if _catalog == null or not _catalog.has_method("get_card_by_id"):
		return

	for raw_section in config.get_sections():
		var section: String = str(raw_section)
		if not section.begins_with("card_"):
			continue
		var card_id := StringName(section.trim_prefix("card_"))
		if _catalog.call("get_card_by_id", card_id) == null:
			config.erase_section(section)


func _card_section(card_id: StringName) -> String:
	return "card_%s" % String(card_id)
