extends SceneTree
## godot --headless --path PROJECT --script res://scripts/qa/game_wind_service_qa.gd
const Wind = preload("res://scripts/world/game_wind_service.gd")
const Clock = preload("res://scripts/world/game_clock_service.gd")
const Strip = preload("res://scripts/ui/seaside_environment_strip.gd")
const QA_PATH := "user://qa_clock_wind_integration.json"
var passes: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, description: String) -> void:
	if value:
		passes += 1
	else:
		failures += 1
		push_error("Wind/Clock QA: " + description)

func _run() -> void:
	await process_frame
	# Existing autoload now mounts these via deferred root.add_child.
	var mounted_clock: Node = root.get_node_or_null("GameClock")
	var mounted_wind: Node = root.get_node_or_null("GameWind")
	if root.get_node_or_null("WorldLocations") != null:
		_check(mounted_clock != null, "autoload clock mounts after root finishes setup")
		_check(mounted_wind != null, "autoload wind mounts after root finishes setup")
		var world: Node = root.get_node("WorldLocations")
		world.call("_mount_environment_services")
		_check(root.get_node_or_null("GameClock") == mounted_clock and root.get_node_or_null("GameWind") == mounted_wind, "deferred environment mount is idempotent")
		var strip = Strip.new()
		root.add_child(strip)
		var projected: Dictionary = strip.read_state({"spot": "Ocean Spot 2", "location": "Beach"})
		_check(str(projected.get("clock", "N/A")) != "N/A", "desktop/mobile header receives authoritative clock")
		_check(str(projected.get("wind", "N/A")) != "N/A", "desktop/mobile header receives wind data")
		strip.queue_free()
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(QA_PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(QA_PATH + suffix))
	var wind = Wind.new()
	root.add_child(wind)
	for t in [0, 1, 480, 481, 1440, 90000]:
		var state: Dictionary = wind.get_snapshot_at_minutes(t)
		_check(bool(state.get("available",false)), "wind available at minute %d" % t)
		_check(float(state.speed_mps) >= 0.0 and float(state.speed_mps) <= Wind.MAX_SPEED_MPS, "bounded speed %d" % t)
		_check(not is_nan(float(state.bearing_degrees)) and not is_inf(float(state.bearing_degrees)), "valid direction %d" % t)
		_check(state.display == wind.get_snapshot_at_minutes(t).display, "deterministic output %d" % t)
	var a: Dictionary = wind.get_snapshot_at_minutes(480)
	var b: Dictionary = wind.get_snapshot_at_minutes(481)
	_check(absf(float(a.speed_mps) - float(b.speed_mps)) < 0.20, "speed changes smoothly minute-to-minute")
	_check(absf(float(a.bearing_degrees) - float(b.bearing_degrees)) < 4.0, "heading changes smoothly minute-to-minute")
	var saved = Clock.new()
	saved.set_save_path(QA_PATH)
	root.add_child(saved)
	saved.set_process(false)
	saved.set_clock(3, 11, 42)
	_check(saved.save_to_disk(), "clock persist")
	var loaded = Clock.new()
	loaded.set_save_path(QA_PATH)
	root.add_child(loaded)
	loaded.set_process(false)
	_check(loaded.get_snapshot().total_minutes == saved.get_snapshot().total_minutes, "clock restoration")
	_check(wind.get_snapshot_at_minutes(int(loaded.get_snapshot().total_minutes)).display == wind.get_snapshot_at_minutes(int(saved.get_snapshot().total_minutes)).display, "wind reproducible after reload")
	for c in [saved, loaded]:
		c._dirty = false
		c.queue_free()
	wind.queue_free()
	await process_frame
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(QA_PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(QA_PATH + suffix))
	print("Wind/Clock QA: %d/%d checks passed" % [passes, passes+failures])
	quit(0 if failures == 0 else 1)
