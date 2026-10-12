extends Node
## QA-only fake GameClock: no access to real user:// clock saves.
signal clock_changed(snapshot: Dictionary)
var total_minutes: int = 480

func get_snapshot() -> Dictionary:
	return {"total_minutes": total_minutes}

func set_minute(value: int) -> void:
	total_minutes = value
	clock_changed.emit(get_snapshot())
