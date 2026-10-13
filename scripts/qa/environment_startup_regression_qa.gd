extends SceneTree
## Godot 4.x:
## --headless --path PROJECT --script res://scripts/qa/environment_startup_regression_qa.gd
## Independent regression for detached ecology services and clock JSON saves.
## Uses ONLY user://qa_environment_startup_clock.json, never production saves.

const EnvironmentService = preload("res://scripts/fishing_environment_service.gd")
const ClockService = preload("res://scripts/world/game_clock_service.gd")
const SAVE_PATH: String = "user://qa_environment_startup_clock.json"

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("Environment startup QA: " + label)


func _clean() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_raw_json(payload: String) -> bool:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(payload)
	file.close()
	return true


func _run() -> void:
	_clean()
	# This used to generate engine errors at fishing_environment_service.gd
	# lines 82 and 85 because the environment node is NOT in the SceneTree.
	var detached: Node = EnvironmentService.new()
	_check(not detached.is_inside_tree(), "fixture is detached")
	var detached_state: Dictionary = detached.call("get_ecology_snapshot") as Dictionary
	_check(detached_state.has("clock_available"), "detached snapshot safely built")
	var root_clock: Node = root.get_node_or_null("GameClock")
	var root_wind: Node = root.get_node_or_null("GameWind")
	if root_clock != null and root_clock.has_method("get_snapshot"):
		_check(bool(detached_state.get("clock_available", false)), "detached snapshot reads mounted clock")
	if root_wind != null and root_wind.has_method("get_snapshot"):
		_check(bool(detached_state.get("wind_available", false)), "detached snapshot reads mounted wind")
	root.add_child(detached)
	var attached_state: Dictionary = detached.call("get_ecology_snapshot") as Dictionary
	_check(attached_state.has("clock_available"), "attached snapshot safely built")
	detached.queue_free()

	var writer: Node = ClockService.new()
	writer.call("set_save_path", SAVE_PATH)
	writer.call("set_clock", 3, 9, 17)
	_check(bool(writer.call("save_to_disk")), "clock saves valid JSON")
	var reader: Node = ClockService.new()
	reader.call("set_save_path", SAVE_PATH)
	_check(bool(reader.call("load_from_disk")), "saved JSON accepted on reload")
	_check(int(reader.call("get_day")) == 3 and int(reader.call("get_hour")) == 9 and int(reader.call("get_minute")) == 17, "clock day and time persisted")

	_check(_write_raw_json("{\"version\":1,\"total_minutes\":480,\"partial_seconds\":0.5}"), "write numeric JSON fixture")
	_check(bool(reader.call("load_from_disk")) and int(reader.call("get_hour")) == 8, "integer-valued JSON number parses")
	_check(_write_raw_json("{\"version\":1,\"total_minutes\":480.5,\"partial_seconds\":0.5}"), "write fractional JSON fixture")
	_check((reader.call("_parse_save", SAVE_PATH) as Dictionary).is_empty(), "fractional minute count rejected")
	writer.free()
	reader.free()
	await process_frame
	_clean()
	print("Environment startup QA: %d/%d passed" % [passed, passed + failed])
	quit(0 if failed == 0 else 1)
