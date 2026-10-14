extends SceneTree
## Environmental Integration v3: isolated real-scene lifecycle and save continuity.
## Run with a Windows PowerShell path to your installed Godot executable.
## Creates a disposable user-data directory; NEVER reads production saves.

const RainScene = preload("res://actors/FishingRainVFX.tscn")
const MainScene = preload("res://actors/FishingTestScene_V2.tscn")

class PendingWorldEnvironment:
	extends Node
	var _live_weather_enabled: bool = true
	var _weather_source: Node = null
	func get_active_tags() -> PackedStringArray:
		return PackedStringArray(["calm", "clear"])
	func enable_live_weather(_enabled: bool = true) -> void:
		pass

class PendingFishing:
	extends Node
	var fishing_environment_service: Node = null


var passed: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	var folder: String = "EnvironmentalIntegrationV3QA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/custom_user_dir_name", folder)
	if not OS.get_user_data_dir().ends_with(folder) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		push_error("Environmental Integration v3 QA: isolated userdata unavailable; refusing to run")
		quit(1)
		return
	print("Environmental Integration v3 isolated userdata: ", OS.get_user_data_dir())
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(description)
		push_error("Environmental Integration v3 QA: " + description)


func frames(count: int = 3) -> void:
	for _index in range(count):
		await process_frame


func _minute_with_condition(weather: Node, condition: StringName) -> int:
	for window in range(1, 160):
		var minute: int = window * 240 + 30
		var snapshot: Dictionary = weather.call("get_snapshot_at_minutes", minute) as Dictionary
		if StringName(snapshot.get("condition_id", "")) == condition:
			return minute
	return -1


func _set_minute(clock: Node, minute: int) -> bool:
	if minute < 0:
		return false
	var day: int = int(minute / 1440) + 1
	var day_minute: int = minute % 1440
	return bool(clock.call("set_clock", day, int(day_minute / 60), day_minute % 60))


func _scene_rain(scene: Node) -> Node3D:
	return scene.get_node_or_null("World/FishingRainVFX") as Node3D


func _force_auto_on_test_rain(node: Node) -> void:
	# Authored scenes may deliberately retain Rain/Storm Preview from visual
	# tuning. The integration test must exercise *Auto*, independently of an
	# artist's saved Inspector values. SceneTree.node_added fires as the node
	# enters the tree, before its _ready() initializes weather intensity.
	# Do not modify the packed scene or any production Inspector values.
	if node.name == &"FishingRainVFX" and node.has_method("_poll_weather"):
		node.set("weather_mode", 0)
		node.set("enabled", true)


func _check_snapshot(scene: Node, condition: StringName, label: String) -> void:
	var fishing: Node = scene.get_node_or_null("Game/Fishing")
	var environment: Node = null
	if fishing != null:
		environment = fishing.get("fishing_environment_service") as Node
	var rain: Node3D = _scene_rain(scene)
	check(environment != null, label + " has fishing environment service")
	check(rain != null, label + " has world-owned rain")
	if environment == null or rain == null:
		return
	var snapshot: Dictionary = environment.call("get_world_snapshot") as Dictionary
	var shared: Dictionary = snapshot.get("weather", {}) as Dictionary
	check(StringName(shared.get("condition_id", "")) == condition, label + " shares authoritative weather")
	var tags: PackedStringArray = environment.call("get_active_tags") as PackedStringArray
	check(tags.has(String(condition)), label + " propagates weather to fish ecology")
	check(rain.get_parent() == scene.get_node("World"), label + " rain belongs to World, not fishing")
	rain.call("_poll_weather")
	check(bool(rain.call("is_raining")) == (condition != &"calm"), label + " visible precipitation agrees with gameplay")
	var clock: Node = root.get_node_or_null("GameClock")
	if clock != null:
		check(int((snapshot.get("clock", {}) as Dictionary).get("total_minutes", -1)) == int((clock.call("get_snapshot") as Dictionary).get("total_minutes", -2)), label + " uses same game clock")


func _run() -> void:
	# Validate the specific startup race without mounting new global services.
	var fixture: Node3D = Node3D.new()
	var fixture_world: Node3D = Node3D.new()
	fixture_world.name = "World"
	fixture.add_child(fixture_world)
	var fixture_game: Node = Node.new()
	fixture_game.name = "Game"
	fixture.add_child(fixture_game)
	var fixture_fishing: PendingFishing = PendingFishing.new()
	fixture_fishing.name = "Fishing"
	fixture_game.add_child(fixture_fishing)
	var pending_env: PendingWorldEnvironment = PendingWorldEnvironment.new()
	fixture_fishing.add_child(pending_env)
	fixture_fishing.fishing_environment_service = pending_env
	var delayed: Node3D = RainScene.instantiate() as Node3D
	# v2 already established this rule: QA must not inherit an authored
	# Rain Preview / Storm Preview mode from the saved rain scene.
	delayed.set("weather_mode", 0)
	delayed.set("enabled", true)
	fixture_world.add_child(delayed) # Detached fixture: no root world weather.
	check((delayed.call("_weather_tags") as PackedStringArray).is_empty(), "unbound live service cannot masquerade as authoritative Calm")
	delayed.call("_poll_weather")
	check(not bool(delayed.get("_weather_initialized")), "missing provider does not initialize Auto as Clear")
	delayed.set("weather_mode", 2)
	delayed.call("_poll_weather")
	check(bool(delayed.get("_weather_initialized")) and is_equal_approx(float(delayed.get("_rain_level")), 1.0), "Inspector preview still initializes immediately")
	fixture.free()

	await frames(5)
	var locations: Node = root.get_node_or_null("WorldLocations")
	var clock: Node = root.get_node_or_null("GameClock")
	var wind: Node = root.get_node_or_null("GameWind")
	var weather: Node = root.get_node_or_null("GameWeather")
	check(locations != null and clock != null and wind != null and weather != null, "authoritative world services mounted")
	if locations == null or clock == null or wind == null or weather == null:
		_finish()
		return
	var rain_minute: int = _minute_with_condition(weather, &"rain")
	var storm_minute: int = _minute_with_condition(weather, &"tempest")
	var calm_minute: int = _minute_with_condition(weather, &"calm")
	check(rain_minute >= 0 and storm_minute >= 0 and calm_minute >= 0, "schedule contains every supported condition")
	if rain_minute < 0 or storm_minute < 0 or calm_minute < 0:
		_finish()
		return
	check(_set_minute(clock, rain_minute), "clock advances to known rain window")
	check(bool(clock.call("save_to_disk")), "isolated game clock saved")
	var saved_weather: Dictionary = weather.call("get_snapshot") as Dictionary
	var saved_wind: Dictionary = wind.call("get_snapshot") as Dictionary
	check(StringName(saved_weather.get("condition_id", "")) == &"rain", "global weather reads updated clock immediately")

	# Rain is dynamically mounted by PlayableLocationScene._ready(), not
	# authored as a child of the main scene. Force the test's Auto mode at
	# node-entry time, BEFORE rain._ready(), including subsequent scene swaps.
	node_added.connect(_force_auto_on_test_rain)
	var scene: Node3D = MainScene.instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await frames(4)
	_check_snapshot(scene, &"rain", "beach startup")
	var rain: Node3D = _scene_rain(scene)
	if rain != null:
		check(bool(rain.get("_weather_initialized")), "rain initial weather state established")
		check(is_equal_approx(float(rain.get("_rain_level")), 1.0), "joining rainy world starts fully raining without replaying a fade")

	var mode: Node = scene.get_node_or_null("Game/GameMode")
	var zone: Area3D = scene.get_node_or_null("World/FishZone_V2") as Area3D
	if mode != null and zone != null and rain != null:
		mode.call("enter_fishing", zone)
		_check_snapshot(scene, &"rain", "fishing mode")
		mode.call("exit_fishing")
		_check_snapshot(scene, &"rain", "return to exploration")
	else:
		check(false, "fishing mode, authored zone and rain exist for entry/exit test")

	# Weather changes are instantaneous for gameplay, while VFX blends.
	check(_set_minute(clock, storm_minute), "clock advances to tempest")
	_check_snapshot(scene, &"tempest", "tempest change")
	if rain != null:
		check(is_equal_approx(float(rain.get("_target_storm_level")), 1.0), "storm fade target is full intensity")
	check(_set_minute(clock, calm_minute), "clock advances to calm")
	_check_snapshot(scene, &"calm", "calm change")
	if rain != null:
		check(is_equal_approx(float(rain.get("_target_rain_level")), 0.0), "clear weather fades rain out")

	# Reload the clock from isolated disk, then change the authored location.
	check(bool(clock.call("load_from_disk")), "clock reloaded from isolated save")
	check((clock.call("get_snapshot") as Dictionary).get("total_minutes") == rain_minute, "save restores exact game minute")
	check(weather.call("get_snapshot") == saved_weather, "weather reproducible after save reload")
	check(wind.call("get_snapshot") == saved_wind, "wind reproducible after save reload")
	var before_clock: Node = clock
	var before_weather: Node = weather
	var destination: Resource = locations.call("get_location", &"wyndia_ocean_outpost") as Resource
	check(destination != null, "ocean outpost registered")
	if destination != null:
		var path: String = str(destination.get("scene_path"))
		var packed: PackedScene = load(path) as PackedScene
		check(packed != null, "ocean location scene available")
		if packed != null:
			# Direct scene swap tests environmental ownership, not travel unlocks.
			# This avoids altering inventory, progression or fishing saves.
			current_scene = null
			scene.queue_free()
			await frames(3)
			var ocean: Node3D = packed.instantiate() as Node3D
			root.add_child(ocean)
			current_scene = ocean
			await frames(4)
			check(locations.get("current_location") == destination, "destination location context rebound")
			check(root.get_node_or_null("GameClock") == before_clock and root.get_node_or_null("GameWeather") == before_weather, "travel keeps singleton services, does not recreate weather")
			_check_snapshot(ocean, &"rain", "ocean after scene swap")
			var ocean_rain: Node3D = _scene_rain(ocean)
			if ocean_rain != null:
				check(is_equal_approx(float(ocean_rain.get("_rain_level")), 1.0), "destination joins rainy weather without fade-in")
			current_scene = null
			ocean.queue_free()
			await frames(3)
	else:
		current_scene = null
		scene.queue_free()
		await frames(3)
	_finish()


func _finish() -> void:
	if node_added.is_connected(_force_auto_on_test_rain):
		node_added.disconnect(_force_auto_on_test_rain)
	print("Environmental Integration v3 QA: %d passed, %d failed" % [passed, failures.size()])
	for failure in failures:
		print("  FAILED: " + failure)
	quit(0 if failures.is_empty() else 1)
