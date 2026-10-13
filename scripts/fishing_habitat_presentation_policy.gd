extends RefCounted
## Environmental Gameplay v3 — pure, bounded presentation adjustment.
## This policy does NOT move the lure, modify casts, alter tide/current services,
## select fish, or replace existing lure-action quality. It only evaluates how
## the existing presentation translates into the local water conditions.
## Tide already affects local water/current and fish-zone density elsewhere;
## do NOT add a second global tide multiplier here.

const MIN_MULTIPLIER: float = 0.88
const MAX_MULTIPLIER: float = 1.12


static func evaluate(
    action: LureActionProfile,
    presentation: Dictionary,
    ecology: Dictionary,
    lure_position: Vector3,
    rod_position: Vector3,
    current_depth: float,
    total_depth: float
) -> Dictionary:
    var neutral: Dictionary = {
        "multiplier": 1.0,
        "label": "NEUTRAL",
        "available": false,
        "relative_retrieve_ratio": float(presentation.get("retrieve_speed_ratio", 0.0)),
        "flow_alignment": 0.0,
        "surface_chop_0_1": 0.0,
        "visibility_0_1": 0.5,
        "depth_ratio_0_1": 0.5,
        "note": "Existing lure quality remains authoritative.",
    }
    if action == null or ecology.is_empty():
        return neutral
    var has_current: bool = bool(ecology.get("current_available", false))
    var has_wind: bool = bool(ecology.get("wind_available", false))
    var has_clock: bool = bool(ecology.get("clock_available", false))
    if not has_current and not has_wind and not has_clock:
        return neutral

    var depth_ratio: float = 0.5
    if total_depth > 0.0:
        depth_ratio = clampf(current_depth / total_depth, 0.0, 1.0)
    var surface_access: float = clampf((0.40 - depth_ratio) / 0.40, 0.0, 1.0)
    var speed: float = clampf(float(presentation.get("retrieve_speed_ratio", 0.0)), 0.0, 2.0)
    var flow_alignment: float = 0.0
    var relative_speed: float = speed
    if has_current:
        var water_current: Vector2 = ecology.get("current_velocity_xz", Vector2.ZERO)
        var toward_rod: Vector2 = Vector2(
            rod_position.x - lure_position.x, rod_position.z - lure_position.z
        )
        if toward_rod.length_squared() > 0.00001:
            # Project-authored velocity units, not claimed to be metres/second.
            # Flow WITH retrieve lowers lure speed relative to water;
            # opposing flow increases it. Limit impact before quality scoring.
            flow_alignment = clampf(
                water_current.dot(toward_rod.normalized()) / 0.9, -1.0, 1.0
            )
            relative_speed = clampf(speed - flow_alignment * 0.24, 0.0, 2.0)

    var adjustment: float = 0.0
    var motion: int = int(action.motion_style)
    # Mild bonus/penalty for relative-water speed moving closer/further from the
    # lure family's intended action. The main presentation system still judges
    # raw retrieve, twitch and pause timing. No invented physical movement.
    if has_current and speed > 0.02:
        var target: float = _target_speed(motion)
        var before_distance: float = absf(speed - target)
        var after_distance: float = absf(relative_speed - target)
        adjustment += clampf((before_distance - after_distance) * 0.15, -0.055, 0.055)

    var wave: float = clampf(float(ecology.get("wave_proxy_0_1", 0.0)), 0.0, 1.0) if has_wind else 0.0
    var visibility: float = clampf(float(ecology.get("visual_detection_0_1", 0.5)), 0.0, 1.0)
    # Rough water makes an already noisy surface lure harder to distinguish;
    # some gentle ripple can mask the angler. There is no universal wind bonus.
    if motion == LureActionProfile.MotionStyle.POP or motion == LureActionProfile.MotionStyle.BOB:
        adjustment += surface_access * (0.025 * minf(wave / 0.35, 1.0) - 0.085 * clampf((wave - 0.45) / 0.55, 0.0, 1.0))
    # Flash lures require light to be visually conspicuous. A slow spoon with
    # little available light does not suddenly become universally more effective.
    if has_clock and (motion == LureActionProfile.MotionStyle.SPOON or motion == LureActionProfile.MotionStyle.SPIN):
        adjustment += clampf((visibility - 0.45) * 0.055, -0.025, 0.030)
    # A moving, wobbling presentation can remain mechanically distinctive in
    # somewhat poorer visibility. Keep this VERY small; no artificial rain buff.
    if motion == LureActionProfile.MotionStyle.WOBBLE:
        adjustment += 0.012 * (1.0 - visibility) if has_clock else 0.0

    var multiplier: float = clampf(1.0 + adjustment, MIN_MULTIPLIER, MAX_MULTIPLIER)
    return {
        "multiplier": multiplier,
        "label": "ASSISTED" if multiplier > 1.02 else ("CHALLENGED" if multiplier < 0.98 else "NEUTRAL"),
        "available": true,
        "relative_retrieve_ratio": relative_speed,
        "flow_alignment": flow_alignment,
        "surface_chop_0_1": wave,
        "visibility_0_1": visibility,
        "depth_ratio_0_1": depth_ratio,
        "current_available": has_current,
        "wind_available": has_wind,
        "clock_available": has_clock,
        "note": "Small physical-presentation proxy; tide/current and species effects are not duplicated.",
    }


static func _target_speed(motion: int) -> float:
    match motion:
        LureActionProfile.MotionStyle.BOB:
            return 0.20
        LureActionProfile.MotionStyle.POP:
            return 0.24
        LureActionProfile.MotionStyle.GLIDE:
            return 0.35
        LureActionProfile.MotionStyle.SWIM:
            return 0.58
        LureActionProfile.MotionStyle.WOBBLE:
            return 0.68
        LureActionProfile.MotionStyle.SPIN:
            return 0.78
        LureActionProfile.MotionStyle.SPOON:
            return 0.50
        _:
            return 0.50
