extends SceneTree
## Godot 4.x: --headless --path PROJECT --script res://scripts/qa/environment_ecology_integration_qa.gd
## Non-mutating: no save file writes; no gameplay camera, lure, world or UI changes.

const Policy = preload("res://scripts/fishing_ecology_policy.gd")
const Env = preload("res://scripts/fishing_environment_service.gd")
const Current = preload("res://scripts/fishing_current_service.gd")
const Catalog = preload("res://scripts/fishing_environment_catalog.gd")

var passed: int = 0
var failed: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("Ecology QA: " + label)


func _state(minute: int, flow: float = 0.3, tags: PackedStringArray = PackedStringArray()) -> Dictionary:
	return Policy.build_snapshot(
		{"total_minutes": minute},
		{"speed_mps": 3.5, "velocity_xz": Vector2(2.0, 1.0)},
		{"active": true, "water_level_ratio": 0.7, "phase_id": &"incoming"},
		Vector2(flow, 0.0),
		tags,
		"ocean_2"
	)


func _run() -> void:
	var dawn := _state(390)
	var noon := _state(720)
	var night := _state(0)
	_check(float(noon.daylight_0_1) > float(dawn.daylight_0_1), "noon brighter than dawn")
	_check(float(dawn.twilight_0_1) > float(noon.twilight_0_1), "dawn twilight exceeds noon")
	_check(float(night.night_0_1) > float(noon.night_0_1), "night longer darkness")
	_check(noon.tide_phase_id == &"incoming", "tidal phase remains authoritative")
	_check(noon.spot_id == "ocean_2", "spot identity forwarded")
	_check(is_equal_approx(float(noon.flow_ratio_0_1), 0.3), "authored current flow index")
	_check(is_equal_approx(float(noon.wind_speed_mps), 3.5), "authoritative wind speed")
	_check(noon.wind_velocity_xz == Vector2(2.0, 1.0), "wind vector unchanged")
	_check(noon.current_velocity_xz == Vector2(0.3, 0.0), "current vector unchanged")
	_check(not bool(noon.unsafe_storm), "calm not classified dangerous")
	_check(bool(noon.clock_available), "clock provenance exposed")
	_check(bool(noon.wind_available), "wind provenance exposed")
	_check(_state(720, 0.3, PackedStringArray(["rain"])).turbidity_proxy_0_1 > noon.turbidity_proxy_0_1, "rain produces estimated turbidity proxy")
	_check(_state(720, 0.3, PackedStringArray(["storm"])).unsafe_storm, "storm safety flag")
	_check(float(_state(720, 0.3, PackedStringArray(["storm"])).visual_light_0_1) < float(noon.visual_light_0_1), "storm reduces estimated visual light")
	_check(_state(720) == _state(720), "deterministic repeated snapshot")

	var fish := FishData.new()
	fish.species_id = &"qa_example_species"
	_check(is_equal_approx(Policy.species_activity_multiplier(fish, noon), 1.0), "unchanged legacy species neutral at noon")
	_check(is_equal_approx(Policy.species_activity_multiplier(fish, night), 1.0), "unchanged legacy species neutral at night")
	fish.ecological_activity_cycle = 1
	_check(Policy.species_activity_multiplier(fish, noon) > Policy.species_activity_multiplier(fish, night), "opt-in diurnal fish responds to light")
	fish.ecological_activity_cycle = 2
	_check(Policy.species_activity_multiplier(fish, dawn) > Policy.species_activity_multiplier(fish, noon), "opt-in twilight fish seeks dawn")
	fish.ecological_activity_cycle = 3
	_check(Policy.species_activity_multiplier(fish, night) > Policy.species_activity_multiplier(fish, noon), "opt-in nocturnal fish responds to darkness")
	fish.ecological_activity_cycle = 0
	fish.ecological_flow_niche = 1
	_check(Policy.species_activity_multiplier(fish, _state(720, 0.1)) > Policy.species_activity_multiplier(fish, _state(720, 0.9)), "low-flow species favors slower current")
	fish.ecological_flow_niche = 2
	_check(Policy.species_activity_multiplier(fish, _state(720, 0.5)) > Policy.species_activity_multiplier(fish, _state(720, 1.0)), "moderate-flow species prefers intermediate movement")
	fish.ecological_flow_niche = 3
	_check(Policy.species_activity_multiplier(fish, _state(720, 0.9)) > Policy.species_activity_multiplier(fish, _state(720, 0.1)), "flow specialist prefers stronger current")
	fish.ecological_flow_niche = 0
	fish.ecological_visibility_niche = 1
	_check(Policy.species_activity_multiplier(fish, noon) > Policy.species_activity_multiplier(fish, night), "visual specialist prefers daylight")
	fish.ecological_visibility_niche = 2
	_check(Policy.species_activity_multiplier(fish, night) > Policy.species_activity_multiplier(fish, noon), "low-light specialist prefers darkness")
	fish.ecological_activity_cycle = 3
	fish.ecological_flow_niche = 3
	for ecology in [night, noon, dawn, _state(720, 1.2, PackedStringArray(["storm"]))]:
		var multiplier: float = Policy.species_activity_multiplier(fish, ecology)
		_check(multiplier >= Policy.MIN_SPECIES_MULTIPLIER and multiplier <= Policy.MAX_SPECIES_MULTIPLIER, "complex combinations remain bounded")

	var host := Node.new()
	host.name = "EnvironmentEcologyQAFixture"
	root.add_child(host)
	var current := Current.new()
	host.add_child(current)
	var env := Env.new()
	host.add_child(env)
	var spot := FishingSpotData.new()
	spot.spot_id = &"ecology_qa"
	spot.current_direction = Vector2(1.0, 0.0)
	spot.current_speed = 0.3
	current.set_spot(spot)
	env.set_spot(spot)
	env.set_current_service(current)
	var catalogue := Catalog.new()
	env.configure(catalogue)
	var observed: Dictionary = env.get_ecology_snapshot()
	_check(observed.spot_id == "ecology_qa", "environment service propagates spot")
	_check((observed.current_velocity_xz as Vector2).distance_to(current.sample_spot_at_uv(spot, Vector2(0.5, 0.5), 0.0)) < 0.00001, "snapshot uses existing current service")
	fish.ecological_activity_cycle = 0
	fish.ecological_flow_niche = 0
	fish.ecological_visibility_niche = 0
	var entry := FishSpawnEntry.new()
	entry.fish = fish
	var context: Dictionary = env.get_selection_context([entry])
	_check(is_equal_approx(float((context.species_multipliers as Dictionary).get("qa_example_species", -1.0)), 1.0), "default fish selection unchanged")
	_check(env.get_debug_snapshot().has("ecology"), "ecology inspectable without separate world state")
	host.queue_free()
	print("Environmental ecology integration QA: %d/%d passed" % [passed, passed + failed.size()])
	for failure in failed:
		print("FAIL: " + failure)
	quit(0 if failed.is_empty() else 1)
