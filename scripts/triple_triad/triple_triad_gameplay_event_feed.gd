extends RefCounted
class_name TripleTriadGameplayEventFeed

const DEFAULT_CAPACITY := 32

var _capacity: int = DEFAULT_CAPACITY
var _sequence: int = 0
var _events: Array[Dictionary] = []


func initialize(capacity: int = DEFAULT_CAPACITY) -> void:
	_capacity = maxi(1, capacity)
	_sequence = 0
	_events.clear()


func push_event(
	event_type: StringName,
	title: String,
	detail: String = "",
	payload: Dictionary = {},
	priority: int = 0
) -> Dictionary:
	_sequence += 1
	var event := {
		"sequence": _sequence,
		"type": String(event_type),
		"title": title,
		"detail": detail,
		"priority": priority,
		"payload": payload.duplicate(true),
	}
	_events.append(event)
	while _events.size() > _capacity:
		_events.pop_front()
	return event.duplicate(true)


func get_pending_events() -> Array:
	var result: Array = []
	for event in _events:
		result.append(event.duplicate(true))
	return result


func pop_next_event() -> Dictionary:
	if _events.is_empty():
		return {}
	var event: Dictionary = _events.pop_front()
	return event.duplicate(true)


func clear() -> void:
	_events.clear()


func size() -> int:
	return _events.size()
