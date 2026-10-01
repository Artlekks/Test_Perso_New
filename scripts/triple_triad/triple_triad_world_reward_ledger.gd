extends RefCounted
class_name TripleTriadWorldRewardLedger

const DEFAULT_SAVE_PATH := "user://triple_triad_world_delivery.cfg"
const SECTION_META := "meta"
const SECTION_COUNTERS := "counters"
const SECTION_CLAIMS := "claims"
const SCHEMA_VERSION := 2

var _counters: Dictionary = {}
var _claimed_events: Dictionary = {}
var _pending_deliveries: Dictionary = {}
var _save_path: String = DEFAULT_SAVE_PATH


func initialize(save_path: String = DEFAULT_SAVE_PATH) -> void:
	_save_path = save_path
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
	_pending_deliveries.erase(key)
	_save_state()


func begin_delivery(
	event_id: StringName,
	source_type: StringName,
	source_id: StringName,
	card_id: StringName,
	source_context: StringName,
	owned_quantity_before: int
) -> bool:
	var key: String = String(event_id).strip_edges()
	if key.is_empty() or has_claimed(event_id):
		return false
	if _pending_deliveries.has(key):
		var existing: Dictionary = _pending_deliveries[key]
		return (
			str(existing.get("card_id", ""))
			== String(card_id)
		)

	_pending_deliveries[key] = {
		"event_id": key,
		"source_type": String(source_type),
		"source_id": String(source_id),
		"card_id": String(card_id),
		"source_context": String(source_context),
		"owned_quantity_before": maxi(
			0,
			owned_quantity_before
		),
		"created_unix": int(Time.get_unix_time_from_system()),
	}
	if not _save_state():
		_pending_deliveries.erase(key)
		return false
	return true


func get_pending_delivery(
	event_id: StringName
) -> Dictionary:
	var key: String = String(event_id).strip_edges()
	if key.is_empty() or not _pending_deliveries.has(key):
		return {}
	return (
		_pending_deliveries[key] as Dictionary
	).duplicate(true)


func get_pending_deliveries() -> Array:
	var result: Array = []
	for raw_event_id in _pending_deliveries.keys():
		var delivery = _pending_deliveries[raw_event_id]
		if delivery is Dictionary:
			result.append(
				(delivery as Dictionary).duplicate(true)
			)
	result.sort_custom(func(a, b):
		return str(a.get("event_id", "")) < str(
			b.get("event_id", "")
		)
	)
	return result


func complete_delivery(event_id: StringName) -> bool:
	var key: String = String(event_id).strip_edges()
	if key.is_empty():
		return false
	_claimed_events[key] = true
	_pending_deliveries.erase(key)
	return _save_state()


func clear_pending_delivery(event_id: StringName) -> bool:
	var key: String = String(event_id).strip_edges()
	if key.is_empty():
		return false
	var changed: bool = _pending_deliveries.erase(key)
	if changed:
		return _save_state()
	return false


func reset_event(event_id: StringName) -> bool:
	var key: String = String(event_id).strip_edges()
	if key.is_empty():
		return false
	var changed: bool = false
	if _pending_deliveries.erase(key):
		changed = true
	if _claimed_events.erase(key):
		changed = true
	if not changed:
		return true
	return _save_state()


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
		"pending_deliveries": get_pending_deliveries(),
	}


func _load_state() -> void:
	_counters.clear()
	_claimed_events.clear()
	_pending_deliveries.clear()

	var config := ConfigFile.new()
	var error_code: Error = config.load(_save_path)
	if error_code != OK:
		return

	var loaded_version: int = int(
		config.get_value(
			SECTION_META,
			"schema_version",
			1
		)
	)
	if loaded_version not in [1, SCHEMA_VERSION]:
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


	if loaded_version >= 2:
		var raw_pending = config.get_value(
			"pending_deliveries",
			"values",
			{}
		)
		if raw_pending is Dictionary:
			for raw_key in (raw_pending as Dictionary).keys():
				var key: String = str(raw_key).strip_edges()
				var raw_delivery = (
					raw_pending as Dictionary
				).get(raw_key, {})
				if key.is_empty() or not (raw_delivery is Dictionary):
					continue
				var delivery: Dictionary = (
					raw_delivery as Dictionary
				).duplicate(true)
				var card_id: String = str(
					delivery.get("card_id", "")
				).strip_edges()
				if card_id.is_empty():
					continue
				delivery["event_id"] = key
				delivery["owned_quantity_before"] = maxi(
					0,
					int(
						delivery.get(
							"owned_quantity_before",
							0
						)
					)
				)
				_pending_deliveries[key] = delivery


func _save_state() -> bool:
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
	config.set_value(
		"pending_deliveries",
		"values",
		_pending_deliveries.duplicate(true)
	)
	var error_code: Error = config.save(_save_path)
	if error_code != OK:
		push_warning(
			"TripleTriadWorldRewardLedger: could not save %s (error %d)."
			% [_save_path, int(error_code)]
		)
		return false
	return true
