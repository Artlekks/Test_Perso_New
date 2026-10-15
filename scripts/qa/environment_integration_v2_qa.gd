extends SceneTree
## Run: godot --headless --path . --script res://scripts/qa/environment_integration_v2_qa.gd
## Scene-local fixtures; never touch production clock, saves, or fish state.

const Policy = preload("res://scripts/environment_fx/environment_weather_presentation_policy.gd")
const RainScene = preload("res://actors/FishingRainVFX.tscn")
const LegacyOverlay = preload("res://scripts/environment_fx/environment_overlay.gd")
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")

class FakeEnvironment:
	extends Node
	var tags: PackedStringArray = PackedStringArray(["calm"])

	func get_active_tags() -> PackedStringArray:
		return tags


class FakeFishing:
	extends Node
	var fishing_environment_service: Node = null


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
		push_error("Environmental Integration v2 QA: " + label)


func _run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	check(Policy.target_levels("clear") == Vector2.ZERO, "clear has no rain or storm")
	check(Policy.target_levels("rain") == Vector2(1.0, 0.0), "rain has full rain without storm")
	check(Policy.target_levels("storm") == Vector2.ONE, "tempest visual target has rain and storm")
	check(is_equal_approx(Policy.step_level(0.0, 1.0, 1.0, 4.0, 5.0), 0.25), "rain rises in controlled seconds")
	check(is_equal_approx(Policy.step_level(1.0, 0.0, 2.0, 2.0, 4.0), 0.5), "rain fades out gradually")
	check(is_equal_approx(Policy.step_level(0.25, 1.0, 5.0, 0.0, 4.0), 1.0), "instant fade remains configurable")
	check(is_equal_approx(Policy.step_level(0.8, 0.0, 20.0, 2.0, 4.0), 0.0), "large delta doesn't overshoot")
	check(Policy.should_emit(0.4, 0.0), "rain particles remain during fade-out")
	check(not Policy.should_emit(0.0, 0.0), "clear stops rain particles")
	check(is_equal_approx(Policy.splash_rate_factor(1.0, 0.0), 1.0), "settled rain preserves impact rate")
	check(is_equal_approx(Policy.splash_rate_factor(1.0, 1.0), 1.3), "settled storm preserves 1.3x rate")
	check(is_equal_approx(Policy.splash_rate_factor(0.0, 1.0), 0.0), "no rain means no new impacts")

	var fixture: Node3D = Node3D.new()
	fixture.name = "V2VisualFixture"
	root.add_child(fixture)
	var world: Node3D = Node3D.new()
	world.name = "World"
	fixture.add_child(world)
	var game: Node = Node.new()
	game.name = "Game"
	fixture.add_child(game)
	var fishing: FakeFishing = FakeFishing.new()
	fishing.name = "Fishing"
	game.add_child(fishing)
	var environment: FakeEnvironment = FakeEnvironment.new()
	fishing.add_child(environment)
	fishing.fishing_environment_service = environment
	var rain: Node3D = RainScene.instantiate() as Node3D
	# A developer may have saved FishingRainVFX.tscn in Rain/Storm Preview.
	# Force Auto BEFORE entering the tree so _ready() initializes from the
	# fixture's calm gameplay tags. This test must never depend on Inspector
	# preview state or require artists to change their approved scene settings.
	rain.set("weather_mode", 0)
	rain.set("enabled", true)
	world.add_child(rain)
	check(is_equal_approx(float(rain.get("drop_width")), 0.003), "approved 0.003 drop width unchanged")
	check(is_equal_approx(float(rain.get("drop_opacity")), 0.7), "approved 0.7 opacity unchanged")
	check(is_equal_approx(float(rain.get("splash_pixel_size")), 0.003), "approved small ripple width unchanged")
	check(int(rain.get("max_simultaneous_splashes")) == 100, "approved splash budget unchanged")
	check(not bool(rain.call("is_raining")), "calm gameplay tags mean clear weather")

	environment.tags = PackedStringArray(["rain", "wet"])
	rain.call("_poll_weather")
	check(bool(rain.call("is_raining")), "world visuals respond to gameplay rain")
	check(is_equal_approx(float(rain.get("_target_rain_level")), 1.0), "rain requests full strength")
	rain.call("_update_visual_weather", 1.25)
	check(is_equal_approx(float(rain.get("_rain_level")), 0.5), "live rain fades in, not instant pop")
	rain.call("_update_visual_weather", 1.25)
	check(is_equal_approx(float(rain.get("_rain_level")), 1.0), "settled rain reaches original intensity")

	environment.tags = PackedStringArray(["tempest", "storm"])
	rain.call("_poll_weather")
	rain.call("_update_visual_weather", 3.0)
	check(is_equal_approx(float(rain.get("_storm_level")), 1.0), "tempest visual emphasis blends in")

	environment.tags = PackedStringArray(["calm", "clear"])
	rain.call("_poll_weather")
	rain.call("_update_visual_weather", 2.0)
	check(is_equal_approx(float(rain.get("_rain_level")), 0.5), "clear weather fades rain out")
	check(Policy.should_emit(float(rain.get("_rain_level")), float(rain.get("_target_rain_level"))), "rain still emits halfway through fade")
	rain.call("_update_visual_weather", 2.0)
	check(is_equal_approx(float(rain.get("_rain_level")), 0.0), "clear completes fade-out")

	rain.set("weather_mode", 2) # Existing rain preview stays independent of gameplay weather.
	rain.call("_poll_weather")
	check(is_equal_approx(float(rain.get("_target_rain_level")), 1.0), "Inspector rain preview overrides calm")
	rain.set("weather_mode", 1)
	rain.call("_poll_weather")
	check(is_equal_approx(float(rain.get("_target_rain_level")), 0.0), "Inspector clear preview overrides rain")

	# GameWeather may not have mounted yet in a direct --script session;
	# validate the fallback if the world provider is available.
	rain.set("weather_mode", 0)
	environment.tags = PackedStringArray()
	var world_weather: Node = root.get_node_or_null("GameWeather")
	if world_weather != null and world_weather.has_method("get_snapshot"):
		var global_tags: PackedStringArray = world_weather.call("get_snapshot").get("tags", PackedStringArray())
		check(rain.call("_weather_tags") == global_tags, "world rain reads GameWeather without fishing tags")

	var overlay: Control = LegacyOverlay.new()
	check(not bool(overlay.get("draw_legacy_weather_particles")), "legacy 2D weather stays disabled")
	overlay.free()
	fixture.free()

	print("Environmental Integration v2 QA: %d passed, %d failed" % [passed, failures.size()])
	for failure in failures:
		print("  FAILED: " + failure)
	Isolation.emit_result("environment_integration_v2_qa", passed, passed + failures.size(),
		failures.size(), Node.get_orphan_node_ids().size())
	quit(0 if failures.is_empty() else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
