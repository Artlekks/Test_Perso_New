extends SceneTree
## Environmental v4 current-phase regression.
## Run headless in the complete FRESH3 project. No save, camera or UI changes.

const EnvironmentServiceScript = preload("res://scripts/fishing_environment_service.gd")
const CurrentServiceScript = preload("res://scripts/fishing_current_service.gd")
const TideServiceScript = preload("res://scripts/fishing_tide_service.gd")
const ClockFixtureScript = preload("res://scripts/qa/current_tide_clock_fixture.gd")
const HabitatPolicyScript = preload("res://scripts/fishing_habitat_presentation_policy.gd")

var passed: int = 0
var failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
    _run.call_deferred()


func _check(ok: bool, description: String) -> void:
    if ok:
        passed += 1
    else:
        failures.append(description)
        push_error("Current phase sync QA: " + description)


func _horizontal(value: Vector3) -> Vector2:
    return Vector2(value.x, value.z)


func _run() -> void:
    var fixture: Node = Node.new()
    fixture.name = "EnvironmentCurrentSyncQA"
    root.add_child(fixture)

    var fake_clock: Node = ClockFixtureScript.new()
    fixture.add_child(fake_clock)
    var tide: FishingTideService = TideServiceScript.new() as FishingTideService
    fixture.add_child(tide)
    var current: FishingCurrentService = CurrentServiceScript.new() as FishingCurrentService
    fixture.add_child(current)
    var environment_service: Node = EnvironmentServiceScript.new()
    fixture.add_child(environment_service)

    # Real authored Ocean 2 has gusts AND spatial fast/calm/eddy fields.
    var spot: FishingSpotData = load("res://data/bof4/spots/ocean_2.tres") as FishingSpotData
    if spot == null:
        _check(false, "Ocean 2 spot resource loaded")
        _finish(fixture)
        return
    _check(spot.current_gust_strength > 0.0, "fixture has nonzero gusts")
    _check(spot.current_gust_period_seconds > 0.0, "fixture has gust period")
    _check(spot.get_valid_current_field_count() >= 3, "fixture has spatial fields")

    tide.set_spot(spot)
    tide.set_clock_service(fake_clock)
    current.set_spot(spot)
    current.set_tide_service(tide)
    environment_service.set_spot(spot)
    environment_service.set_tide_service(tide)
    environment_service.set_current_service(current)

    # Give the current service the same spatial bounds used by lure physics.
    var bounds: FishSwimBounds = FishSwimBounds.new()
    var shape_node: CollisionShape3D = CollisionShape3D.new()
    shape_node.name = "BoundsShape3D"
    var box: BoxShape3D = BoxShape3D.new()
    box.size = Vector3(20.0, 6.0, 20.0)
    shape_node.shape = box
    bounds.add_child(shape_node)
    fixture.add_child(bounds)
    current.set_swim_bounds(bounds)

    var positions: Array[Vector3] = [
        bounds.normalized_uv_to_world(Vector2(0.58, 0.38), 0.0),
        bounds.normalized_uv_to_world(Vector2(0.22, 0.72), 0.0),
        bounds.normalized_uv_to_world(Vector2(0.79, 0.69), 0.0),
    ]
    var period: float = spot.current_gust_period_seconds
    var phases: Array[float] = [0.0, period * 0.25, period * 0.50, period * 0.75]

    for position in positions:
        for phase in phases:
            var physical_current: Vector2 = _horizontal(current.sample_current_velocity(position, phase))
            var ecology: Dictionary = environment_service.get_ecology_snapshot(position, phase)
            var ecological_current: Vector2 = ecology.get("current_velocity_xz", Vector2.ZERO) as Vector2
            _check(ecological_current.distance_to(physical_current) < 0.00001,
                "ecology and physical water flow agree at position %s, phase %.3f" % [str(position), phase])
            _check(str(ecology.get("current_sample_scope", "")) == "local_lure",
                "local lure provenance is preserved")

    # Gust phase must actually change the live source; constant t=0 would fail.
    var reference_point: Vector3 = positions[0]
    var early: Vector2 = _horizontal(current.sample_current_velocity(reference_point, 0.0))
    var later: Vector2 = _horizontal(current.sample_current_velocity(reference_point, period * 0.50))
    _check(early.distance_to(later) > 0.00001, "reference current changes during gust cycle")
    var ecology_early: Dictionary = environment_service.get_ecology_snapshot(reference_point, 0.0)
    var ecology_later: Dictionary = environment_service.get_ecology_snapshot(reference_point, period * 0.50)
    _check((ecology_early.get("current_velocity_xz", Vector2.ZERO) as Vector2).distance_to(
        ecology_later.get("current_velocity_xz", Vector2.ZERO) as Vector2) > 0.00001,
        "ecology reflects changing gust, not frozen phase zero")

    # Selection and lure presentation must inherit the exact supplied phase.
    var fish: FishData = FishData.new()
    fish.species_id = &"qa_current_specialist"
    fish.ecological_flow_niche = 3
    var entry: FishSpawnEntry = FishSpawnEntry.new()
    entry.fish = fish
    var entries: Array = [entry]
    var bait: BaitData = BaitData.new()
    var action: LureActionProfile = LureActionProfile.new()
    action.motion_style = LureActionProfile.MotionStyle.WOBBLE
    bait.action_profile = action
    var presentation: Dictionary = {"retrieve_speed_ratio": 0.4}
    var rod_position: Vector3 = Vector3.ZERO
    for phase in phases:
        var ecology: Dictionary = environment_service.get_ecology_snapshot(reference_point, phase)
        var selection: Dictionary = environment_service.get_selection_context(entries, reference_point, phase)
        var species_values: Dictionary = selection.get("species_multipliers", {}) as Dictionary
        var actual_species: float = float(species_values.get("qa_current_specialist", -1.0))
        var expected_species: float = environment_service.get_species_selection_multiplier(fish, ecology)
        _check(is_equal_approx(actual_species, expected_species),
            "fish selection uses synchronized phase %.3f" % phase)
        var actual_lure: Dictionary = environment_service.get_lure_environment_presentation_snapshot(
            bait, reference_point, rod_position, presentation, 0.2, 1.0, phase)
        var expected_lure: Dictionary = HabitatPolicyScript.evaluate(
            action, presentation, ecology, reference_point, rod_position, 0.2, 1.0)
        _check(is_equal_approx(float(actual_lure.get("multiplier", -1.0)),
            float(expected_lure.get("multiplier", -2.0))),
            "lure presentation uses synchronized phase %.3f" % phase)
        _check(is_equal_approx(float(actual_lure.get("flow_alignment", -2.0)),
            float(expected_lure.get("flow_alignment", -3.0))),
            "lure flow alignment uses synchronized phase %.3f" % phase)

    # Existing no-argument API and live defaults remain functional.
    var center: Dictionary = environment_service.get_ecology_snapshot()
    _check(str(center.get("current_sample_scope", "")) == "spot_center",
        "legacy center sampling signature preserved")
    var live: Dictionary = environment_service.get_ecology_snapshot(reference_point)
    var live_velocity: Vector2 = _horizontal(current.sample_current_velocity(reference_point))
    _check((live.get("current_velocity_xz", Vector2.ZERO) as Vector2).distance_to(live_velocity) < 0.002,
        "live sampling follows same ticking current as lure physics")

    _finish(fixture)


func _finish(fixture: Node) -> void:
    fixture.queue_free()
    print("Environment current phase sync v4 QA: %d/%d checks passed" % [passed, passed + failures.size()])
    for failure in failures:
        print("FAIL: " + failure)
    quit(0 if failures.is_empty() else 1)
