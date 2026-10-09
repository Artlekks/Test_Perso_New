extends RefCounted
## Platform boundary only. Gameplay never depends on native window ownership.
var helper_pid := -1
var command_path := ""
var status_path := ""
var sequence := 0
var last_request: Dictionary = {}
var requested_at := 0

func supported() -> bool:
	return OS.get_name() == "Windows" and DisplayServer.get_name() != "headless" and not OS.has_feature("web")

func request(docked: bool, window: Window, edge := "right", requested_size := Vector2i.ZERO) -> Error:
	if not supported(): return ERR_UNAVAILABLE
	var target_size: Vector2i = requested_size if requested_size!=Vector2i.ZERO else window.size
	var next := {"docked": docked, "edge":edge, "hwnd": DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window.get_window_id()), "width": target_size.x, "height": target_size.y}
	if next == last_request and helper_pid > 0 and OS.is_process_running(helper_pid): return OK
	last_request = next.duplicate()
	sequence += 1
	requested_at = Time.get_ticks_msec()
	next.sequence = sequence
	if command_path.is_empty():
		var cache := OS.get_environment("FISHING_COMPANION_IPC")
		if cache.is_empty(): cache = OS.get_cache_dir()
		var directory := cache.path_join("FishingCompanion-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
		if DirAccess.make_dir_recursive_absolute(directory) != OK: return ERR_CANT_CREATE
		command_path = directory.path_join("command.json")
		status_path = directory.path_join("status.json")
	var error := _write(next)
	if error != OK: return error
	if helper_pid <= 0 or not OS.is_process_running(helper_pid):
		if not docked: return OK
		var python := OS.get_environment("FISHING_COMPANION_PYTHON")
		if python.is_empty():
			python = OS.get_environment("USERPROFILE").path_join(".cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe")
		if not FileAccess.file_exists(python): python = "python"
		helper_pid = OS.create_process(python, [ProjectSettings.globalize_path("res://tools/desktop/windows_appbar.py"), "--pid", str(OS.get_process_id()), "--command", command_path, "--status", status_path], false)
		if helper_pid <= 0: return ERR_CANT_FORK
	return OK

func read_status() -> Dictionary:
	if helper_pid > 0 and not OS.is_process_running(helper_pid):
		return {"registered":false,"sequence":sequence,"error":"Windows AppBar helper exited; reservation released."}
	if status_path.is_empty() or not FileAccess.file_exists(status_path):
		if helper_pid > 0 and Time.get_ticks_msec()-requested_at > 8000:
			return {"error":"Windows AppBar helper did not acknowledge startup."}
		return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(status_path))
	return value if value is Dictionary else {}

func _write(payload: Dictionary) -> Error:
	var temp := command_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload))
	file.close()
	return DirAccess.rename_absolute(temp, command_path)

func close() -> void:
	# Do not kill the helper: let its finally/ABM_REMOVE run. It also watches our
	# native process handle for crashes, forced termination and early shutdown.
	if not command_path.is_empty(): _write({"close": true})
