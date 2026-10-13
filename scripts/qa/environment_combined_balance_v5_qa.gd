extends SceneTree
## Environmental v5 — read-only combined-conditions regression / balancing diagnostics.
## Godot 4.x:
##   --headless --path PROJECT --script res://scripts/qa/environment_combined_balance_v5_qa.gd
## Uses real catalog, tide, current and FishData resources. No saves, game camera,
## lure trajectory, global clock or live fishing scene state are modified.

const EcologyPolicyScript = preload("res://scripts/fishing_ecology_policy.gd")
const HabitatPolicyScript = preload("res://scripts/fishing_habitat_presentation_policy.gd")
const EnvironmentServiceScript = preload("res://scripts/fishing_environment_service.gd")
const TideServiceScript = preload("res://scripts/fishing_tide_service.gd")
const CurrentServiceScript = preload("res://scripts/fishing_current_service.gd")
const CatalogScript = preload("res://scripts/fishing_environment_catalog.gd")
const ActionProfileScript = preload("res://scripts/lure_action_profile.gd")

const CATALOG_PATH: String = "res://data/bof4/environment/all_environment_conditions.tres"
const FISH_DIRECTORY: String = "res://data/bof4/fish/"
const SPECIES_MIN: float = 0.65
const SPECIES_MAX: float = 1.35
const PRESENTATION_MIN: float = 0.88
const PRESENTATION_MAX: float = 1.12

var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _review_flags: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(description)
		push_error("Environment v5 QA: " + description)


func _within(value: float, low: float, high: float) -> bool:
	# NaN and infinities fail these comparisons without depending on newer APIs.
	return value >= low - 0.00001 and value <= high + 0.00001


func _scenario(
	label: String, minute: int, weather: String, tide_position: float,
	current_speed: float, wind_speed: float, wind_direction: Vector2
) -> Dictionary:
	return {
		"label": label,
		"minute": minute,
		"weather": weather,
		"tide_position": tide_position,
		"current_speed": current_speed,
		"wind_speed": wind_speed,
		"wind_direction": wind_direction,
	}


func _scenarios() -> Array:
	# These are stress cases, not forecasts or physically measured conditions.
	# Distinct tide positions deliberately include both slack and strong flow.
	return [
		_scenario("calm_noon_low_slack", 720, "calm", 0.00, 0.20, 0.0, Vector2.RIGHT),
		_scenario("calm_noon_incoming", 720, "calm", 0.25, 0.40, 3.0, Vector2.RIGHT),
		_scenario("clear_dawn_incoming", 390, "calm", 0.25, 0.40, 2.0, Vector2.RIGHT),
		_scenario("clear_dusk_outgoing", 1110, "calm", 0.75, 0.55, 4.0, Vector2.LEFT),
		_scenario("calm_night_high_slack", 30, "calm", 0.50, 0.20, 1.0, Vector2.RIGHT),
		_scenario("rain_day_incoming", 720, "rain", 0.25, 0.50, 5.0, Vector2.RIGHT),
		_scenario("rain_dusk_outgoing", 1110, "rain", 0.75, 0.60, 7.0, Vector2.LEFT),
		_scenario("rain_night_low_slack", 60, "rain", 0.00, 0.20, 4.0, Vector2.RIGHT),
		_scenario("storm_day_incoming", 720, "tempest", 0.25, 0.85, 12.0, Vector2.LEFT),
		_scenario("storm_dusk_outgoing", 1110, "tempest", 0.75, 0.80, 11.0, Vector2.RIGHT),
		_scenario("storm_night_high_slack", 60, "tempest", 0.50, 0.30, 10.0, Vector2.LEFT),
		_scenario("strong_clear_crosswind", 720, "calm", 0.25, 0.65, 13.0, Vector2.UP),
		_scenario("quiet_clear_day_high_slack", 720, "calm", 0.50, 0.05, 0.0, Vector2.RIGHT),
		_scenario("quiet_clear_night_outgoing", 1380, "calm", 0.75, 0.05, 0.0, Vector2.RIGHT),
	]


func _load_fish() -> Array[FishData]:
	var result: Array[FishData] = []
	var ids: Dictionary = {}
	var files: PackedStringArray = DirAccess.get_files_at(FISH_DIRECTORY)
	for filename in files:
		if not filename.ends_with(".tres"):
			continue
		var fish: FishData = load(FISH_DIRECTORY + filename) as FishData
		_check(fish != null, "Fish resource loads: " + filename)
		if fish == null:
			continue
		var species_id: String = fish.get_stable_species_id()
		_check(not ids.has(species_id), "Unique species ID: " + species_id)
		ids[species_id] = true
		result.append(fish)
	_check(result.size() == 30, "30 canonical fish resources available")
	return result


func _run() -> void:
	var catalogue: CatalogScript = load(CATALOG_PATH) as CatalogScript
	_check(catalogue != null, "Environment catalog loads")
	if catalogue == null:
		_finish()
		return
	_check(catalogue.is_valid_catalog(), "Environment catalog definitions valid")
	for condition_id in ["calm", "rain", "tempest"]:
		_check(catalogue.has_condition(StringName(condition_id)), "Weather available: " + condition_id)
	var fish_list: Array[FishData] = _load_fish()
	if fish_list.is_empty():
		_finish()
		return

	# An isolated SceneTree fixture is sufficient for existing service APIs.
	var host: Node = Node.new()
	host.name = "EnvironmentV5BalanceFixture"
	root.add_child(host)
	var tide: FishingTideService = TideServiceScript.new() as FishingTideService
	host.add_child(tide)
	tide.set_auto_advance(false)
	var current: FishingCurrentService = CurrentServiceScript.new() as FishingCurrentService
	host.add_child(current)
	var environment: Node = EnvironmentServiceScript.new()
	host.add_child(environment)
	var spot: FishingSpotData = FishingSpotData.new()
	spot.spot_id = &"v5_balance_ocean"
	spot.water_type = FishingSpotData.WaterType.OCEAN
	spot.current_direction = Vector2.RIGHT
	spot.current_speed = 0.4
	tide.set_spot(spot)
	current.set_spot(spot)
	current.set_tide_service(tide)
	environment.call("configure", catalogue)
	environment.call("set_spot", spot)
	environment.call("set_tide_service", tide)
	environment.call("set_current_service", current)

	var actions: Array[LureActionProfile] = []
	for motion_id in range(7):
		var action: LureActionProfile = ActionProfileScript.new() as LureActionProfile
		action.set("motion_style", motion_id)
		actions.append(action)
	var scenarios: Array = _scenarios()
	var effective_min: float = 999.0
	var effective_max: float = 0.0
	var capped_weights: int = 0
	var capped_bites: int = 0
	var total_species_samples: int = 0
	var total_lure_samples: int = 0
	var neutral_species: int = 0

	print("BALANCE_COLUMNS|case|weather|time|tide|wind_mps|current_speed|bite_mid|selection_min|selection_max|presentation_min|presentation_max|fish_available")
	for scenario in scenarios:
		var name: String = str(scenario.get("label", "unnamed"))
		var weather_id: String = str(scenario.get("weather", "calm"))
		var minute: int = int(scenario.get("minute", 720))
		var wind_speed: float = float(scenario.get("wind_speed", 0.0))
		var wind_direction: Vector2 = scenario.get("wind_direction", Vector2.RIGHT)
		spot.current_speed = float(scenario.get("current_speed", 0.4))
		current.set_spot(spot)
		tide.set_cycle_position(float(scenario.get("tide_position", 0.25)))
		environment.call("activate_condition", StringName(weather_id))
		# The old dawn/night condition IDs remain manually authored; apply
		# only when their named time range matches this synthetic test case.
		if minute >= 330 and minute < 480:
			environment.call("activate_condition", &"dawn")
		else:
			environment.call("deactivate_condition", &"dawn")
		if minute >= 1200 or minute < 300:
			environment.call("activate_condition", &"night")
		else:
			environment.call("deactivate_condition", &"night")
		var tide_data: Dictionary = tide.get_snapshot()
		var local_velocity: Vector2 = current.sample_current_at_uv(Vector2(0.5, 0.5), 0.0)
		var ecology: Dictionary = EcologyPolicyScript.build_snapshot(
			{"total_minutes": minute},
			{"available": true, "speed_mps": wind_speed, "velocity_xz": wind_direction * wind_speed},
			tide_data,
			local_velocity,
			environment.call("get_active_tags") as PackedStringArray,
			"v5_balance_ocean"
		)
		ecology["current_available"] = true
		_check(bool(tide_data.get("active", false)), name + ": tide active")
		_check(ecology.get("tide_phase_id", &"none") == tide_data.get("phase_id", &"none"), name + ": tide snapshot consistent")
		_check(_within(float(ecology.get("flow_ratio_0_1", -1.0)), 0.0, 1.0), name + ": normalized flow")
		_check(_within(float(ecology.get("visual_detection_0_1", -1.0)), 0.0, 1.0), name + ": visibility proxy")
		_check(_within(float(ecology.get("wave_proxy_0_1", -1.0)), 0.0, 1.0), name + ": wave proxy")
		_check(str(ecology.get("quality", "")) == "authored_simplification", name + ": interpretation documented")
		var repeated: Dictionary = EcologyPolicyScript.build_snapshot(
			{"total_minutes": minute},
			{"available": true, "speed_mps": wind_speed, "velocity_xz": wind_direction * wind_speed},
			tide_data,
			local_velocity,
			environment.call("get_active_tags") as PackedStringArray,
			"v5_balance_ocean"
		)
		repeated["current_available"] = true
		_check(ecology == repeated, name + ": repeatability")

		var bite: float = float(environment.call("get_bite_activity_multiplier", 0.5, 1.0))
		_check(_within(bite, 0.25, 2.5), name + ": bounded bite activity")
		var quality: Dictionary = environment.call("get_specimen_generation_context") as Dictionary
		_check(_within(float(quality.get("environment_quality_bonus_chance", -1.0)), 0.0, 0.5), name + ": quality roll chance")
		_check(int(quality.get("environment_quality_bonus_rolls", -1)) <= 2, name + ": quality roll count")
		var fight: Dictionary = environment.call("get_fight_modifiers") as Dictionary
		_check(_within(float(fight.get("fish_pressure_multiplier", -1.0)), 0.5, 1.5), name + ": fish pressure bounded")

		var local_species_min: float = 999.0
		var local_species_max: float = -1.0
		var fish_available: int = 0
		for fish in fish_list:
			var ecology_weight: float = EcologyPolicyScript.species_activity_multiplier(fish, ecology)
			_check(_within(ecology_weight, SPECIES_MIN, SPECIES_MAX), name + ": ecology clamp " + fish.get_stable_species_id())
			if fish.ecological_activity_cycle == 0 and fish.ecological_flow_niche == 0 and fish.ecological_visibility_niche == 0:
				_check(is_equal_approx(ecology_weight, 1.0), name + ": neutral ecology " + fish.get_stable_species_id())
				neutral_species += 1
			var selection_weight: float = float(environment.call("get_species_selection_multiplier", fish, ecology))
			_check(_within(selection_weight, 0.0, 4.0), name + ": bounded selection " + fish.get_stable_species_id())
			local_species_min = minf(local_species_min, selection_weight)
			local_species_max = maxf(local_species_max, selection_weight)
			effective_min = minf(effective_min, selection_weight)
			effective_max = maxf(effective_max, selection_weight)
			if selection_weight > 0.0:
				fish_available += 1
			if selection_weight >= 3.99999:
				capped_weights += 1
			total_species_samples += 1
		_check(fish_available > 0, name + ": no environmental species deadlock")
		if bite >= 2.49999:
			capped_bites += 1

		var local_lure_min: float = 999.0
		var local_lure_max: float = -1.0
		for action in actions:
			for retrieve_speed in [0.20, 0.50, 0.78]:
				for depth in [0.10, 0.75]:
					var lure_result: Dictionary = HabitatPolicyScript.evaluate(
						action,
						{"retrieve_speed_ratio": retrieve_speed},
						ecology,
						Vector3(5.0, 0.0, 0.0), Vector3.ZERO,
						depth, 1.0
					)
					var lure_weight: float = float(lure_result.get("multiplier", -1.0))
					_check(_within(lure_weight, PRESENTATION_MIN, PRESENTATION_MAX), name + ": bounded lure presentation")
					local_lure_min = minf(local_lure_min, lure_weight)
					local_lure_max = maxf(local_lure_max, lure_weight)
					total_lure_samples += 1
		print("BALANCE|%s|%s|%d|%s|%.1f|%.2f|%.3f|%.3f|%.3f|%.3f|%.3f|%d" % [
			name, weather_id, minute, str(tide_data.get("phase_id", &"none")),
			wind_speed, spot.current_speed, bite, local_species_min, local_species_max,
			local_lure_min, local_lure_max, fish_available
		])

	if capped_weights > 0:
		_review_flags.append("Selection cap reached: %d of %d species/scenario samples" % [capped_weights, total_species_samples])
	if capped_bites > 0:
		_review_flags.append("Bite cap reached: %d of %d scenarios" % [capped_bites, scenarios.size()])
	# Research/design issue; NOT a failing regression. These time conditions
	# remain author-assigned independently of the persistent GameClock.
	_review_flags.append("Dawn/night legacy condition tags are not clock-driven in production")
	_review_flags.append("Weather rain/tempest retain global bite, quality and tier bonuses; species-specific tuning remains incomplete")
	_review_flags.append("No angler safety gate is connected to unsafe_storm; do not interpret this as safe real-world guidance")

	_check(total_species_samples == scenarios.size() * 30, "Complete species matrix coverage")
	_check(total_lure_samples == scenarios.size() * 7 * 3 * 2, "Complete lure matrix coverage")
	_check(neutral_species == scenarios.size() * 26, "All 26 unprofiled species remain ecology-neutral")
	print("BALANCE_SUMMARY|scenarios=%d|species_checks=%d|lure_checks=%d|selection_range=%.3f..%.3f|selection_cap_hits=%d|bite_cap_hits=%d" % [
		scenarios.size(), total_species_samples, total_lure_samples,
		effective_min, effective_max, capped_weights, capped_bites
	])
	for review in _review_flags:
		print("REVIEW_ONLY|" + review)
	host.queue_free()
	_finish()


func _finish() -> void:
	print("Environmental v5 combined balance QA: %d/%d checks passed" % [_checks - _failures.size(), _checks])
	for failure in _failures:
		print("FAIL|" + failure)
	quit(0 if _failures.is_empty() else 1)
