extends RefCounted
class_name TripleTriadPlaytestRecorder

const LOG_PATH := "user://triple_triad_playtest_log.jsonl"


func append(
	event_type: StringName,
	payload: Dictionary = {}
) -> bool:
	var file: FileAccess = null
	if FileAccess.file_exists(LOG_PATH):
		file = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)

	if file == null:
		return false

	var entry := {
		"time": Time.get_datetime_string_from_system(),
		"unix": int(Time.get_unix_time_from_system()),
		"type": String(event_type),
		"payload": payload.duplicate(true),
	}
	file.store_line(JSON.stringify(entry))
	file.close()
	return true


func clear() -> bool:
	if not FileAccess.file_exists(LOG_PATH):
		return true
	return DirAccess.remove_absolute(LOG_PATH) == OK


func get_info() -> Dictionary:
	return {
		"path": LOG_PATH,
		"exists": FileAccess.file_exists(LOG_PATH),
		"size_bytes": (
			FileAccess.get_file_as_bytes(LOG_PATH).size()
			if FileAccess.file_exists(LOG_PATH)
			else 0
		),
	}
