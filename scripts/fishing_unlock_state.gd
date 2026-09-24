extends Node
class_name FishingUnlockState

signal changed
signal flag_granted(flag_id: StringName)

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://fishing_unlocks.json"

var _flags: Dictionary = {}
var _initialized: bool = false


func _ready() -> void:
	initialize()


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	load_from_disk()


func has_flag(flag_id: StringName) -> bool:
	if flag_id == &"":
		return false
	return bool(_flags.get(str(flag_id), false))


func grant_flag(flag_id: StringName, persist: bool = true) -> bool:
	if flag_id == &"" or has_flag(flag_id):
		return false

	_flags[str(flag_id)] = true
	flag_granted.emit(flag_id)
	changed.emit()

	if persist:
		save_to_disk()

	return true


func get_all_flags() -> PackedStringArray:
	var result := PackedStringArray()
	for raw_key in _flags.keys():
		if bool(_flags[raw_key]):
			result.append(str(raw_key))
	result.sort()
	return result


func save_to_disk() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"flags": _flags,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("FishingUnlockState: could not open save file for writing.")
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


func load_from_disk() -> bool:
	_flags.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		changed.emit()
		return true

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("FishingUnlockState: could not open save file for reading.")
		return false

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_warning("FishingUnlockState: invalid save; starting with no flags.")
		return false

	var data: Dictionary = parsed
	if int(data.get("version", 0)) > SAVE_VERSION:
		push_warning("FishingUnlockState: save version is newer than this build.")
		return false

	var loaded_flags = data.get("flags", {})
	if loaded_flags is Dictionary:
		for raw_key in (loaded_flags as Dictionary).keys():
			if bool((loaded_flags as Dictionary)[raw_key]):
				_flags[str(raw_key)] = true

	changed.emit()
	return true


func reset_unlocks(delete_save: bool = true) -> void:
	_flags.clear()
	if delete_save and FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	changed.emit()
