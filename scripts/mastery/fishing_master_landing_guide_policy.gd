extends RefCounted
class_name FishingMasterLandingGuidePolicy

## Teaching policy for Master Landing Guide.
##
## Landing Technique normally opens only after the mastery is known. The master
## lesson deliberately does NOT grant the capability early. Instead it observes
## the same SPENT-fish approach conditions and uses the exact response vocabulary,
## hold time, and difficulty window from FishingLandingTechniquePolicy.

const LandingTechniquePolicy = preload(
	"res://scripts/fishing_landing_technique_policy.gd"
)


static func get_trigger_distance(final_surge_trigger_distance_meters: float) -> float:
	return LandingTechniquePolicy.get_trigger_distance(
		final_surge_trigger_distance_meters
	)


static func should_open_lesson(
	fight_state: StringName,
	distance_meters: float,
	trigger_distance_meters: float,
	attempt_used: bool,
	final_surge_checked: bool,
	final_surge_active: bool
) -> bool:
	if fight_state != &"SPENT":
		return false
	if attempt_used or final_surge_checked or final_surge_active:
		return false
	if is_nan(distance_meters) or is_inf(distance_meters) or distance_meters < 0.0:
		return false
	return distance_meters <= maxf(trigger_distance_meters, 0.05)


static func get_expected_response(fish_lateral: float) -> StringName:
	return LandingTechniquePolicy.get_expected_response(fish_lateral)


static func get_response_window_seconds(
	difficulty_tier: int,
	is_king: bool
) -> float:
	return LandingTechniquePolicy.get_window_seconds(
		difficulty_tier,
		is_king
	)


static func is_response_matching(
	expected_response: StringName,
	fish_lateral: float,
	player_reeling: bool,
	player_steering: float
) -> bool:
	return LandingTechniquePolicy.is_response_matching(
		expected_response,
		fish_lateral,
		player_reeling,
		player_steering
	)


static func advance_match_time(
	current_time: float,
	is_matching: bool,
	delta: float
) -> float:
	return LandingTechniquePolicy.advance_match_time(
		current_time,
		is_matching,
		delta
	)


static func is_response_complete(match_time: float) -> bool:
	return LandingTechniquePolicy.is_response_complete(match_time)


static func get_hold_required_seconds() -> float:
	return LandingTechniquePolicy.RESPONSE_HOLD_SECONDS


static func get_response_label(
	expected_response: StringName,
	fish_lateral: float
) -> String:
	return LandingTechniquePolicy.get_response_label(
		expected_response,
		fish_lateral
	)
