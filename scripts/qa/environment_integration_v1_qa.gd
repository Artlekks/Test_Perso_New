extends SceneTree
## Run: godot --headless --path . --script res://scripts/qa/environment_integration_v1_qa.gd
## Never changes the real GameClock or production save data.

const WeatherScript = preload("res://scripts/world/game_weather_service.gd")
const EnvironmentScript = preload("res://scripts/fishing_environment_service.gd")
const Catalog = preload("res://data/bof4/environment/all_environment_conditions.tres")
const RainScene = preload("res://actors/FishingRainVFX.tscn")
const RainPreviewScene = preload("res://actors/FishingRainVFXPreview.tscn")
const LegacyOverlay = preload("res://scripts/environment_fx/environment_overlay.gd")
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")

class FakeWeather:
	extends Node
	signal weather_changed(snapshot: Dictionary)
	var condition_id: StringName = &"calm"

	func get_snapshot() -> Dictionary:
		return {"available": true, "condition_id": condition_id, "display": str(condition_id)}

	func update_condition(id: StringName) -> void:
		condition_id = id
		weather_changed.emit(get_snapshot())


var passed: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(label)
		push_error("Environment Integration v1 QA: " + label)


func _run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	var weather: Node = WeatherScript.new()
	var at_start: Dictionary = weather.get_snapshot_at_minutes(480)
	check(bool(at_start.get("available", false)), "schedule publishes available weather")
	check([&"calm", &"rain", &"tempest"].has(at_start.get("condition_id", &"")), "only authored weather ids are scheduled")
	check(weather.get_snapshot_at_minutes(480) == at_start, "same clock minute repeats same forecast")
	check(weather.get_snapshot_at_minutes(480 + 4).get("condition_id") == at_start.get("condition_id"), "weather stable inside a window")
	check(int(at_start.get("minutes_until_next_window", 0)) > 0, "schedule exposes window boundary")
	var all_conditions: Dictionary = {}
	for slot in range(80):
		var snapshot: Dictionary = weather.get_snapshot_at_minutes(slot * 240)
		all_conditions[snapshot.get("condition_id")] = true
	check(all_conditions.has(&"calm") and all_conditions.has(&"rain") and all_conditions.has(&"tempest"), "calm/rain/tempest occur across deterministic forecast")
	var future: Dictionary = weather.get_snapshot_at_minutes(240 * 65)
	var reload: Node = WeatherScript.new()
	check(reload.get_snapshot_at_minutes(240 * 65) == future, "reload reproduces weather from persisted GameClock minute")
	weather.free()
	reload.free()

	var manual: Node = EnvironmentScript.new()
	manual.configure(Catalog)
	check((manual.call("get_active_condition_ids") as PackedStringArray).has("calm"), "standalone manual fixture keeps authored default")
	check(bool(manual.activate_condition(&"tempest")), "manual fixture can still select tempest")
	check((manual.call("get_active_tags") as PackedStringArray).has("storm"), "manual fixture is not overwritten by world weather")
	manual.free()

	var source: FakeWeather = FakeWeather.new()
	root.add_child(source)
	var environment: Node = EnvironmentScript.new()
	root.add_child(environment)
	environment.configure(Catalog)
	environment.set_weather_source(source)
	check((environment.get_active_condition_ids() as PackedStringArray).has("calm"), "source starts with calm")
	source.update_condition(&"rain")
	check((environment.get_active_tags() as PackedStringArray).has("rain"), "source rain reaches gameplay tags")
	check(not (environment.get_active_tags() as PackedStringArray).has("calm"), "replacing weather clears old tags")
	var shared: Dictionary = environment.get_world_snapshot()
	check(shared.get("weather", {}).get("condition_id") == &"rain", "shared world snapshot matches gameplay weather")
	check(shared.has("current") and shared.has("wind") and shared.has("clock") and shared.has("tide"), "shared snapshot exposes all environmental sources")
	check(environment.activate_condition(&"tempest"), "manual weather preview still works during live integration")
	check((environment.get_active_tags() as PackedStringArray).has("storm"), "manual preview survives polling")
	source.update_condition(&"calm")
	check((environment.get_active_tags() as PackedStringArray).has("calm"), "next scheduled change restores automatic weather")
	environment.set_weather_source(null)
	source.update_condition(&"rain")
	check((environment.get_active_tags() as PackedStringArray).has("calm"), "unbinding source stops updates")
	environment.free()
	source.free()

	var overlay: Control = LegacyOverlay.new()
	check(not bool(overlay.get("draw_legacy_weather_particles")), "old 2D rain renderer disabled by default")
	overlay.free()
	var rain: Node3D = RainScene.instantiate() as Node3D
	check(int(rain.get("weather_mode")) == 0, "approved rain scene remains in Auto mode")
	check(is_equal_approx(float(rain.get("drop_width")), 0.003), "approved rain thickness untouched")
	check(is_equal_approx(float(rain.get("splash_pixel_size")), 0.003), "approved ripple size untouched")
	check(rain.call("_resolve_weather", PackedStringArray(["calm", "clear"])) == "clear", "Auto follows clear gameplay weather")
	check(rain.call("_resolve_weather", PackedStringArray(["rain"])) == "rain", "Auto follows rainy gameplay weather")
	check(rain.call("_resolve_weather", PackedStringArray(["tempest", "storm"])) == "storm", "Auto follows tempest gameplay weather")
	var preview: Node3D = RainPreviewScene.instantiate() as Node3D
	check(int(preview.get("weather_mode")) == 2 and preview.call("_resolve_weather", PackedStringArray(["calm"])) == "rain", "separate artist preview retains Rain Preview mode")
	check(is_equal_approx(float(preview.get("drop_width")), float(rain.get("drop_width")))
		and is_equal_approx(float(preview.get("drop_opacity")), float(rain.get("drop_opacity")))
		and is_equal_approx(float(preview.get("splash_pixel_size")), float(rain.get("splash_pixel_size")))
		and bool(preview.get("follow_wind_direction")) == bool(rain.get("follow_wind_direction"))
		and is_equal_approx(float(preview.get("wind_angle_influence")), float(rain.get("wind_angle_influence"))), "artist preview inherits approved rain appearance")
	preview.free()
	rain.free()

	print("Environmental Integration v1 QA: %d passed, %d failed" % [passed, failures.size()])
	for failure in failures:
		print("  FAILED: " + failure)
	Isolation.emit_result("environment_integration_v1_qa", passed, passed + failures.size(),
		failures.size(), Node.get_orphan_node_ids().size())
	quit(0 if failures.is_empty() else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
