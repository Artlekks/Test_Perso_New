extends SceneTree
## Standalone Godot 4.x environment v3 regression test.
## Run with --headless --path . --script res://scripts/qa/environment_habitat_presentation_v3_qa.gd
## Keep aliases distinct from native engine class names (e.g. Environment).

const HabitatPolicyScript = preload("res://scripts/fishing_habitat_presentation_policy.gd")
const FishingEnvironmentServiceScript = preload("res://scripts/fishing_environment_service.gd")
const ActionProfileScript = preload("res://scripts/lure_action_profile.gd")

var checks_passed: int = 0
var checks_failed: int = 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _check(condition: bool, description: String) -> void:
    if condition:
        checks_passed += 1
    else:
        checks_failed += 1
        push_error("Environment v3 QA failed: " + description)


func _ecology_sample(flow: Vector2, wave_amount: float, visibility: float) -> Dictionary:
    return {
        "current_available": true,
        "wind_available": true,
        "clock_available": true,
        "current_velocity_xz": flow,
        "wave_proxy_0_1": wave_amount,
        "visual_detection_0_1": visibility,
        "flow_ratio_0_1": clampf(flow.length(), 0.0, 1.0)
    }


func _assess(
    motion_style: int,
    retrieve_speed: float,
    flow: Vector2,
    wave_amount: float = 0.0,
    visibility: float = 0.8,
    depth: float = 0.1
) -> Dictionary:
    var action: LureActionProfile = ActionProfileScript.new()
    action.set("motion_style", motion_style)
    return HabitatPolicyScript.evaluate(
        action,
        {"retrieve_speed_ratio": retrieve_speed},
        _ecology_sample(flow, wave_amount, visibility),
        Vector3(5.0, 0.0, 0.0),
        Vector3.ZERO,
        depth,
        1.0
    )


func _score(value: Dictionary) -> float:
    return float(value.get("multiplier", 1.0))


func _run_tests() -> void:
    var pop_style: int = LureActionProfile.MotionStyle.POP
    var spin_style: int = LureActionProfile.MotionStyle.SPIN
    var wobble_style: int = LureActionProfile.MotionStyle.WOBBLE

    var calm_surface: Dictionary = _assess(pop_style, 0.24, Vector2.ZERO)
    var gentle_surface: Dictionary = _assess(pop_style, 0.24, Vector2.ZERO, 0.25)
    var rough_surface: Dictionary = _assess(pop_style, 0.24, Vector2.ZERO, 0.95)
    _check(is_equal_approx(_score(calm_surface), 1.0), "calm surface neutral")
    _check(_score(gentle_surface) > _score(calm_surface), "gentle chop helps popper")
    _check(_score(rough_surface) < _score(gentle_surface), "rough chop masks popper")

    var deep_surface_lure: Dictionary = _assess(pop_style, 0.24, Vector2.ZERO, 0.95, 0.8, 0.85)
    _check(is_equal_approx(_score(deep_surface_lure), 1.0), "surface effect vanishes at depth")

    # Lure lies at +X and the rod is at the origin. +X flow opposes retrieve.
    var opposing_flow: Dictionary = _assess(wobble_style, 0.40, Vector2(0.8, 0.0))
    var following_flow: Dictionary = _assess(wobble_style, 0.40, Vector2(-0.8, 0.0))
    _check(_score(opposing_flow) > _score(following_flow), "relative lure action responds to flow direction")

    var visible_spinner: Dictionary = _assess(spin_style, 0.78, Vector2.ZERO, 0.0, 0.9)
    var dark_spinner: Dictionary = _assess(spin_style, 0.78, Vector2.ZERO, 0.0, 0.1)
    _check(_score(visible_spinner) > _score(dark_spinner), "flash more visible in light")

    var empty_snapshot: Dictionary = HabitatPolicyScript.evaluate(
        null, {}, {}, Vector3.ZERO, Vector3.ZERO, 0.0, 1.0
    )
    _check(is_equal_approx(_score(empty_snapshot), 1.0), "null action safely neutral")
    _check(not bool(empty_snapshot.get("available", true)), "unavailable inputs reported")

    var sample_styles: Array[int] = [
        LureActionProfile.MotionStyle.GLIDE,
        LureActionProfile.MotionStyle.BOB,
        LureActionProfile.MotionStyle.POP,
        LureActionProfile.MotionStyle.SWIM,
        LureActionProfile.MotionStyle.WOBBLE,
        LureActionProfile.MotionStyle.SPIN,
        LureActionProfile.MotionStyle.SPOON
    ]
    var sample_flows: Array[Vector2] = [Vector2.ZERO, Vector2(2.0, 0.0), Vector2(-2.0, 0.0)]
    var sample_waves: Array[float] = [0.0, 0.5, 1.0]
    for motion_id in sample_styles:
        for sample_flow in sample_flows:
            for sample_wave in sample_waves:
                var assessed: Dictionary = _assess(motion_id, 0.5, sample_flow, sample_wave)
                var multiplier: float = _score(assessed)
                _check(
                    multiplier >= HabitatPolicyScript.MIN_MULTIPLIER
                    and multiplier <= HabitatPolicyScript.MAX_MULTIPLIER,
                    "bounded: style=%d, flow=%s, wave=%s" % [motion_id, str(sample_flow), str(sample_wave)]
                )

    # Verify that the existing no-argument API is preserved and that the
    # explicit optional position requests a location-based sampling scope.
    var environment_instance: Node = FishingEnvironmentServiceScript.new()
    var center_snapshot: Dictionary = environment_instance.get_ecology_snapshot()
    var position_snapshot: Dictionary = environment_instance.get_ecology_snapshot(Vector3(4.0, 0.0, 8.0))
    _check(str(center_snapshot.get("current_sample_scope", "")) == "spot_center", "legacy spot-center API")
    _check(str(position_snapshot.get("current_sample_scope", "")) == "local_lure", "local lure sampling API")
    environment_instance.free()

    print("Environment habitat/presentation v3 QA: %d/%d passed" % [checks_passed, checks_passed + checks_failed])
    quit(0 if checks_failed == 0 else 1)
