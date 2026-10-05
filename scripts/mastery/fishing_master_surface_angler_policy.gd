extends RefCounted
class_name FishingMasterSurfaceAnglerPolicy

## Pure teaching policy for Master Surface Angler.
##
## The lesson observes the already-existing Surface Control event without
## granting the mastery early or changing tension/fish behavior. A qualifying
## surface instability opens the same response window as the real technique,
## and the player must preserve the ordinary run read while keeping the rod low.

const SurfacePolicy = preload("res://scripts/fishing_surface_control_policy.gd")


static func get_expected_response(intent: Dictionary) -> StringName:
	return SurfacePolicy.get_expected_response(intent)


static func is_qualifying_event(
	surface_snapshot: Dictionary,
	intent: Dictionary
) -> bool:
	if not bool(surface_snapshot.get("near_surface", false)):
		return false
	if float(surface_snapshot.get("instability_impulse", 0.0)) <= 0.0:
		return false
	if get_expected_response(intent) == SurfacePolicy.RESPONSE_NONE:
		return false
	return SurfacePolicy.should_start(
		intent,
		float(surface_snapshot.get("current_depth_m", 0.0)),
		float(surface_snapshot.get("total_depth_m", 0.0)),
		0.0
	)


static func get_response_window_seconds(intent: Dictionary) -> float:
	return SurfacePolicy.get_window_seconds(intent)


static func is_response_matching(
	expected_response: StringName,
	intent: Dictionary,
	player_reeling: bool,
	player_steering: float,
	player_tension_bias: float
) -> bool:
	return SurfacePolicy.is_response_matching(
		expected_response,
		intent,
		player_reeling,
		player_steering,
		player_tension_bias
	)


static func advance_match_time(
	current_time: float,
	is_matching: bool,
	delta: float
) -> float:
	return SurfacePolicy.advance_match_time(current_time, is_matching, delta)


static func is_response_complete(match_time: float) -> bool:
	return SurfacePolicy.is_response_complete(match_time)


static func get_hold_required_seconds() -> float:
	return SurfacePolicy.RESPONSE_HOLD_SECONDS


static func get_response_label(response: StringName) -> String:
	return SurfacePolicy.get_response_label(response)
