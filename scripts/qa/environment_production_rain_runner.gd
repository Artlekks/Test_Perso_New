extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const LOCATIONS = [&"beach", &"lyp_lake_outpost", &"river_fishing_outpost"]
var passed := 0
var total := 0

func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	call_deferred("_run")

func _check(label: String, good: bool) -> void:
	total += 1
	passed += int(good)
	print("PRODUCTION_RAIN_CHECK %s %s" % [label, "PASS" if good else "FAIL"])

func _minute_for(weather: Node, wanted: StringName) -> int:
	for window in range(1, 160):
		var minute := window * 240 + 30
		if StringName(weather.call("get_snapshot_at_minutes", minute).get("condition_id", "")) == wanted:
			return minute
	return -1

func _set_minute(clock: Node, minute: int) -> bool:
	if minute < 0:
		return false
	var day_minute := minute % 1440
	return bool(clock.call("set_clock", int(minute / 1440) + 1,
		int(day_minute / 60), day_minute % 60))

func _run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	var clock := root.get_node_or_null("GameClock")
	var weather := root.get_node_or_null("GameWeather")
	var locations := root.get_node_or_null("WorldLocations")
	if clock == null or weather == null or locations == null:
		_check("world authorities available", false)
		_finish()
		return
	var calm := _minute_for(weather, &"calm")
	var rain := _minute_for(weather, &"rain")
	var tempest := _minute_for(weather, &"tempest")
	_check("authored schedule has all conditions", calm >= 0 and rain >= 0 and tempest >= 0)
	for id in LOCATIONS:
		var context: Resource = locations.call("get_location", id) as Resource
		var path := str(context.get("scene_path")) if context != null else ""
		var packed: PackedScene = load(path) as PackedScene if not path.is_empty() else null
		_check(str(id) + " production scene loads", packed != null)
		if packed == null:
			continue
		_set_minute(clock, calm)
		var scene: Node3D = packed.instantiate() as Node3D
		root.add_child(scene)
		current_scene = scene
		for frame in range(4):
			await process_frame
		var effect: Node3D = scene.get_node_or_null("World/FishingRainVFX") as Node3D
		_check(str(id) + " mounts shared Auto rain", effect != null
			and effect.get_parent() == scene.get_node_or_null("World")
			and int(effect.get("weather_mode")) == 0)
		if effect != null:
			effect.call("_poll_weather")
			_check(str(id) + " calm stays dry", not bool(effect.call("is_raining"))
				and is_equal_approx(float(effect.get("_target_rain_level")), 0.0))
			_set_minute(clock, rain)
			effect.call("_poll_weather")
			_check(str(id) + " rain follows world weather", bool(effect.call("is_raining"))
				and is_equal_approx(float(effect.get("_target_rain_level")), 1.0))
			_set_minute(clock, tempest)
			effect.call("_poll_weather")
			_check(str(id) + " tempest targets storm", bool(effect.call("is_raining"))
				and is_equal_approx(float(effect.get("_target_storm_level")), 1.0))
		current_scene = null
		scene.queue_free()
		for frame in range(3):
			await process_frame
	_finish()

func _finish() -> void:
	Isolation.emit_result("environment_production_rain_runner", passed, total,
		total - passed, Node.get_orphan_node_ids().size())
	quit(0 if passed == total else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
