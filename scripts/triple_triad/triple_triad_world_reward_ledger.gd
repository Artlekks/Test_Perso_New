extends RefCounted
class_name TripleTriadWorldRewardLedger

const SAVE_PATH := "user://triple_triad_world_delivery.cfg"
const SECTION_META := "meta"
const SECTION_COUNTERS := "counters"
const SECTION_CLAIMS := "claims"
const SCHEMA_VERSION := 1

var _counters: Dictionary = {}
var _claimed_events: Dictionary = {}


func initialize() -> void:
	_load_state()


func increment_counter(counter_id: StringName) -> int:
	var key: String = String(counter_id)
	if key.is_empty():
		return 0
	var next_value: int = int(_counters.get(key, 0)) + 1
	_counters[key] = next_value
	_save_state()
	return next_value


func get_counter(counter_id: StringName) -> int:
	return int(_counters.get(String(counter_id), 0))


func reset_counter(counter_id: StringName) -> void:
	var key: String = String(counter_id)
	if key.is_empty():
		return
	_counters[key] = 0
	_save_state()


func has_claimed(event_id: StringName) -> bool:
	var key: String = String(event_id)
	if key.is_empty():
		return false
	return bool(_claimed_events.get(key, false))


func mark_claimed(event_id: StringName) -> void:
	var key: String = String(event_id)
	if key.is_empty():
		return
	_claimed_events[key] = true
	_save_state()


func get_snapshot() -> Dictionary:
	var claimed_ids := PackedStringArray()
	for key in _claimed_events.keys():
		if bool(_claimed_events.get(key, false)):
			claimed_ids.append(str(key))
	claimed_ids.sort()

	return {
		"schema_version": SCHEMA_VERSION,
		"counters": _counters.duplicate(true),
		"claimed_event_ids": claimed_ids,
	}


func _load_state() -> void:
	_counters.clear()
	_claimed_events.clear()

	var config := ConfigFile.new()
	var error_code: Error = config.load(SAVE_PATH)
	if error_code != OK:
		return

	if int(config.get_value(SECTION_META, "schema_version", 0)) != SCHEMA_VERSION:
		return

	var raw_counters = config.get_value(SECTION_COUNTERS, "values", {})
	if raw_counters is Dictionary:
		for raw_key in (raw_counters as Dictionary).keys():
			var key: String = str(raw_key)
			if not key.is_empty():
				_counters[key] = maxi(
					0,
					int((raw_counters as Dictionary).get(raw_key, 0))
				)

	var raw_claims = config.get_value(SECTION_CLAIMS, "values", {})
	if raw_claims is Dictionary:
		for raw_key in (raw_claims as Dictionary).keys():
			var key: String = str(raw_key)
			if not key.is_empty():
				_claimed_events[key] = bool(
					(raw_claims as Dictionary).get(raw_key, false)
				)


func _save_state() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION_META, "schema_version", SCHEMA_VERSION)
	config.set_value(
		SECTION_COUNTERS,
		"values",
		_counters.duplicate(true)
	)
	config.set_value(
		SECTION_CLAIMS,
		"values",
		_claimed_events.duplicate(true)
	)
	var error_code: Error = config.save(SAVE_PATH)
	if error_code != OK:
		push_warning(
			"TripleTriadWorldRewardLedger: could not save %s (error %d)."
			% [SAVE_PATH, int(error_code)]
		)
