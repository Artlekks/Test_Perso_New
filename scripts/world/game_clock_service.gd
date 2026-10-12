extends Node
## One authoritative, persistent in-game clock shared by desktop and mobile.
## WorldLocations mounts this service once under /root/GameClock.
## Environment effects remain owned by FishingEnvironmentService; this pass
## deliberately does NOT rewrite time-of-day fishing modifiers.

signal clock_changed(snapshot: Dictionary)
signal day_changed(day_number: int)

const VERSION: int = 1
const MINUTES_PER_DAY: int = 1440
const START_MINUTES: int = 8 * 60  # Day 1, 08:00.
const REAL_SECONDS_PER_GAME_MINUTE: float = 2.0
const AUTOSAVE_REAL_SECONDS: float = 15.0
const DEFAULT_SAVE_PATH: String = "user://game_clock_v1.json"
const MAX_SAVED_MINUTES: int = MINUTES_PER_DAY * 365 * 100

var _total_minutes: int = START_MINUTES
var _partial_seconds: float = 0.0
var _autosave_seconds: float = 0.0
var _save_path: String = DEFAULT_SAVE_PATH
var _dirty: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()
	set_process(true)


func _process(delta: float) -> void:
	# Manual pause and modal menus own the SceneTree pause. A globally live
	# service must explicitly respect that state. Never count offline time.
	if get_tree() == null or get_tree().paused:
		return
	advance_real_seconds(delta)
	if not _dirty:
		return
	_autosave_seconds += maxf(delta, 0.0)
	if _autosave_seconds >= AUTOSAVE_REAL_SECONDS:
		save_to_disk()


func advance_real_seconds(real_seconds: float) -> void:
	if is_nan(real_seconds) or is_inf(real_seconds) or real_seconds <= 0.0:
		return
	_partial_seconds += real_seconds
	var whole_minutes: int = int(floor(_partial_seconds / REAL_SECONDS_PER_GAME_MINUTE))
	if whole_minutes <= 0:
		_dirty = true
		return
	_partial_seconds = fmod(_partial_seconds, REAL_SECONDS_PER_GAME_MINUTE)
	advance_minutes(whole_minutes)


func advance_minutes(minutes: int) -> void:
	if minutes <= 0:
		return
	var previous_day: int = get_day()
	_total_minutes = mini(MAX_SAVED_MINUTES, _total_minutes + minutes)
	_dirty = true
	if get_day() != previous_day:
		day_changed.emit(get_day())
	clock_changed.emit(get_snapshot())


func get_day() -> int:
	return floori(float(_total_minutes) / float(MINUTES_PER_DAY)) + 1


func get_hour() -> int:
	return floori(float(_total_minutes % MINUTES_PER_DAY) / 60.0)


func get_minute() -> int:
	return _total_minutes % 60


func get_period() -> String:
	var hour := get_hour()
	if hour < 5: return "Night"
	if hour < 8: return "Dawn"
	if hour < 12: return "Morning"
	if hour < 17: return "Afternoon"
	if hour < 20: return "Evening"
	return "Night"


func get_clock_text() -> String:
	var hour_12 := get_hour() % 12
	if hour_12 == 0: hour_12 = 12
	return "Day %d · %d:%02d %s" % [get_day(), hour_12, get_minute(), "AM" if get_hour() < 12 else "PM"]


func get_short_clock_text() -> String:
	return "D%d %02d:%02d" % [get_day(), get_hour(), get_minute()]


func get_snapshot() -> Dictionary:
	return {
		"day": get_day(),
		"hour": get_hour(),
		"minute": get_minute(),
		"period": get_period(),
		"display": get_clock_text(),
		"short": get_short_clock_text(),
		"total_minutes": _total_minutes,
	}


func set_clock(day: int, hour: int, minute: int) -> bool:
	if day < 1 or day > 365 * 100 or hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return false
	var previous_day := get_day()
	_total_minutes = (day - 1) * MINUTES_PER_DAY + hour * 60 + minute
	_partial_seconds = 0.0
	_dirty = true
	if previous_day != day: day_changed.emit(day)
	clock_changed.emit(get_snapshot())
	return true


func reset_clock() -> void:
	set_clock(1, 8, 0)
	save_to_disk()


func set_save_path(path: String) -> void:
	# Allows isolated QA saves without modifying production user:// data.
	if path.begins_with("user://") and path.ends_with(".json"):
		_save_path = path


func save_to_disk() -> bool:
	var payload := {
		"version": VERSION,
		"total_minutes": _total_minutes,
		"partial_seconds": _partial_seconds,
	}
	var temp_path := _save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("GameClock: cannot open temporary save file.")
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	file.close()

	var primary := ProjectSettings.globalize_path(_save_path)
	var temporary := ProjectSettings.globalize_path(temp_path)
	var backup := ProjectSettings.globalize_path(_save_path + ".bak")
	var previous_saved := FileAccess.file_exists(_save_path)
	if previous_saved:
		if FileAccess.file_exists(_save_path + ".bak"):
			DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(primary, backup) != OK:
			push_warning("GameClock: could not preserve previous save.")
			return false
	if DirAccess.rename_absolute(temporary, primary) != OK:
		if previous_saved:
			DirAccess.rename_absolute(backup, primary)
		push_warning("GameClock: could not commit save; previous data retained.")
		return false
	_dirty = false
	_autosave_seconds = 0.0
	return true


func load_from_disk() -> bool:
	var primary := _parse_save(_save_path)
	var backup := _parse_save(_save_path + ".bak") if primary.is_empty() else {}
	var loaded: Dictionary = primary if not primary.is_empty() else backup
	if loaded.is_empty():
		if FileAccess.file_exists(_save_path) or FileAccess.file_exists(_save_path + ".bak"):
			push_warning("GameClock: invalid save and backup; starting at Day 1, 08:00.")
		_total_minutes = START_MINUTES
		_partial_seconds = 0.0
		_dirty = false
		_autosave_seconds = 0.0
		clock_changed.emit(get_snapshot())
		return not FileAccess.file_exists(_save_path) and not FileAccess.file_exists(_save_path + ".bak")
	_total_minutes = int(loaded["total_minutes"])
	_partial_seconds = float(loaded["partial_seconds"])
	_dirty = false
	_autosave_seconds = 0.0
	clock_changed.emit(get_snapshot())
	return true


func _parse_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	if parsed.get("version", null) != VERSION:
		return {}
	var minutes = parsed.get("total_minutes", null)
	var remainder = parsed.get("partial_seconds", null)
	if typeof(minutes) != TYPE_INT:
		return {}
	if typeof(remainder) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	var fractional := float(remainder)
	if minutes < 0 or minutes > MAX_SAVED_MINUTES or is_nan(fractional) or is_inf(fractional) or fractional < 0.0 or fractional >= REAL_SECONDS_PER_GAME_MINUTE:
		return {}
	return {"total_minutes": minutes, "partial_seconds": fractional}


func _exit_tree() -> void:
	if _dirty:
		save_to_disk()
