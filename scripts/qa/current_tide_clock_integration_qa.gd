extends SceneTree
## Execute: godot --headless --path . --script res://scripts/qa/current_tide_clock_integration_qa.gd
## Isolated checks: no save mutations, no fishing runtime or camera overrides.

const TideScript = preload("res://scripts/fishing_tide_service.gd")
const CurrentScript = preload("res://scripts/fishing_current_service.gd")
const ClockFixtureScript = preload("res://scripts/qa/current_tide_clock_fixture.gd")
var total: int = 0
var passed: int = 0
var errors: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	total += 1
	if condition:
		passed += 1
	else:
		errors.append(description)
		push_error("CurrentTide QA: " + description)

func _run() -> void:
	var fixture := Node.new()
	fixture.name = "CurrentTideClockQA"
	root.add_child(fixture)
	var fake_clock := ClockFixtureScript.new()
	fixture.add_child(fake_clock)
	var tide := TideScript.new() as FishingTideService
	fixture.add_child(tide)
	var current := CurrentScript.new() as FishingCurrentService
	fixture.add_child(current)
	var ocean := FishingSpotData.new()
	ocean.spot_id = &"qa_ocean"
	ocean.water_type = FishingSpotData.WaterType.OCEAN
	ocean.current_direction = Vector2.RIGHT
	ocean.current_speed = 0.40
	var lake := FishingSpotData.new()
	lake.spot_id = &"qa_lake"
	lake.water_type = FishingSpotData.WaterType.LAKE
	lake.current_direction = Vector2.RIGHT
	lake.current_speed = 0.40
	current.set_spot(ocean)
	current.set_tide_service(tide)
	tide.set_spot(ocean)
	tide.set_clock_service(fake_clock)
	check(is_equal_approx(tide.get_cycle_position(), FishingTideService.DEFAULT_START_POSITION), "clock starts at authored tide phase")
	check(tide.get_snapshot().get("active", false), "ocean tide active")
	var initial_sample := current.sample_current_at_uv(Vector2(0.5, 0.5), 0.0)
	check(initial_sample.length() > 0.0, "authored current remains active")
	var earlier_spot = current.get_spot()
	var start_preview := tide.get_preview_snapshot(ocean)
	check(start_preview.get("active", false), "ocean preview available without mutation")
	check(current.get_spot() == earlier_spot, "preview leaves active spot untouched")
	fake_clock.set_minute(680)
	var advanced := tide.get_cycle_position()
	check(not is_equal_approx(advanced, FishingTideService.DEFAULT_START_POSITION), "clock moves tide phase")
	var advanced_sample := current.sample_current_at_uv(Vector2(0.5, 0.5), 0.0)
	check(absf(advanced_sample.length() - initial_sample.length()) > 0.001, "current responds to clock-driven tidal flow")
	var old_position := tide.get_cycle_position()
	tide._process(500.0)
	check(is_equal_approx(tide.get_cycle_position(), old_position), "tide no longer follows independent real time")
	check(not bool(tide.get_preview_snapshot(lake).get("active", true)), "freshwater preview has no tide")
	var lake_current := current.sample_spot_at_uv(lake, Vector2(0.5, 0.5), 0.0)
	check(is_equal_approx(lake_current.length(), lake.current_speed), "tide cannot affect freshwater current")
	var preview_current := current.sample_spot_at_uv(ocean, Vector2(0.5, 0.5), 0.0)
	check(preview_current.distance_to(advanced_sample) < 0.00001, "preview matches active current at same UV")
	check(current.get_spot() == earlier_spot, "read-only current preview does not rebind fishing spot")
	var restored_clock := ClockFixtureScript.new()
	restored_clock.total_minutes = 680
	fixture.add_child(restored_clock)
	tide.set_clock_service(restored_clock)
	check(is_equal_approx(tide.get_cycle_position(), old_position), "reloaded game minute reproduces tide phase")
	check(tide.get_time_to_next_phase_seconds() > 0.0, "next tide phase has positive forecast")
	var manual_tide := TideScript.new() as FishingTideService
	fixture.add_child(manual_tide)
	manual_tide.set_spot(ocean)
	manual_tide.set_cycle_position(0.25)
	check(manual_tide.get_phase_id() == FishingTideService.PHASE_INCOMING, "legacy Tide Sense fixtures retain manual phase control")
	current.set_tide_service(null)
	fixture.queue_free()
	print("Current + Tide integration QA: %d/%d checks passed" % [passed, total])
	for failure in errors:
		print("FAIL: " + failure)
	quit(0 if errors.is_empty() else 1)
