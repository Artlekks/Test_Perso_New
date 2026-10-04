extends RefCounted
class_name FishingLandingTechniquePolicy

## Landing Technique v1
##
## A spent fish is not automatically safe just because its main stamina is gone.
## Close to shore, a trained angler guides the fish head-first through the final
## approach before the existing Final Surge check. The technique never deletes
## Final Surge: a clean approach only reduces its probability and severity.
##
## The response deliberately reuses existing controls:
## - fish already straight: hold K with neutral A/D
## - fish angled/running right: hold K + steer left
## - fish angled/running left: hold K + steer right

const RESULT_IDLE: StringName = &"idle"
const RESULT_READING: StringName = &"reading"
const RESULT_SUCCESS: StringName = &"success"
const RESULT_MISSED: StringName = &"missed"
const RESULT_CANCELLED: StringName = &"cancelled"

const RESPONSE_NONE: StringName = &"none"
const RESPONSE_STEADY: StringName = &"head_first_steady"
const RESPONSE_COUNTER: StringName = &"head_first_counter"

const STEERING_DEADZONE: float = 0.22
const RESPONSE_HOLD_SECONDS: float = 0.18
const WINDOW_EASY_SECONDS: float = 0.95
const WINDOW_HARD_SECONDS: float = 0.62
const KING_WINDOW_PENALTY_SECONDS: float = 0.08
const DEFAULT_APPROACH_MARGIN_METERS: float = 0.90

const CHANCE_MULTIPLIER_EASY: float = 0.55
const CHANCE_MULTIPLIER_HARD: float = 0.68
const KING_CHANCE_PENALTY: float = 0.08
const STAMINA_MULTIPLIER: float = 0.82
const KING_STAMINA_MULTIPLIER: float = 0.90
const INTENSITY_MULTIPLIER: float = 0.88
const KING_INTENSITY_MULTIPLIER: float = 0.94


static func get_trigger_distance(final_surge_trigger_distance_meters: float) -> float:
	return maxf(
		final_surge_trigger_distance_meters + DEFAULT_APPROACH_MARGIN_METERS,
		final_surge_trigger_distance_meters
	)


static func should_start(
	distance_meters: float,
	trigger_distance_meters: float,
	already_checked: bool,
	final_surge_checked: bool,
	final_surge_active: bool,
	mastery_known: bool
) -> bool:
	if already_checked or final_surge_checked or final_surge_active:
		return false
	if not mastery_known:
		return false
	if is_nan(distance_meters) or is_inf(distance_meters) or distance_meters < 0.0:
		return false
	return distance_meters <= maxf(trigger_distance_meters, 0.05)


static func get_expected_response(fish_lateral: float) -> StringName:
	if absf(fish_lateral) <= STEERING_DEADZONE:
		return RESPONSE_STEADY
	return RESPONSE_COUNTER


static func is_response_matching(
	expected_response: StringName,
	fish_lateral: float,
	player_reeling: bool,
	player_steering: float
) -> bool:
	if not player_reeling:
		return false

	match expected_response:
		RESPONSE_STEADY:
			return absf(player_steering) <= STEERING_DEADZONE

		RESPONSE_COUNTER:
			if absf(fish_lateral) <= STEERING_DEADZONE:
				return false
			if absf(player_steering) <= STEERING_DEADZONE:
				return false
			return signf(player_steering) != signf(fish_lateral)

		_:
			return false


static func get_window_seconds(difficulty_tier: int, is_king: bool) -> float:
	var tier := clampi(difficulty_tier, 1, 5)
	var t := float(tier - 1) / 4.0
	var window := lerpf(WINDOW_EASY_SECONDS, WINDOW_HARD_SECONDS, t)
	if is_king:
		window -= KING_WINDOW_PENALTY_SECONDS
	return maxf(window, 0.48)


static func advance_match_time(
	current_time: float,
	is_matching: bool,
	delta: float
) -> float:
	if not is_matching:
		return 0.0
	return minf(
		maxf(current_time, 0.0) + maxf(delta, 0.0),
		RESPONSE_HOLD_SECONDS
	)


static func is_response_complete(match_time: float) -> bool:
	return match_time >= RESPONSE_HOLD_SECONDS


static func get_final_surge_chance_multiplier(
	difficulty_tier: int,
	is_king: bool
) -> float:
	var tier := clampi(difficulty_tier, 1, 5)
	var t := float(tier - 1) / 4.0
	var multiplier := lerpf(
		CHANCE_MULTIPLIER_EASY,
		CHANCE_MULTIPLIER_HARD,
		t
	)
	if is_king:
		multiplier += KING_CHANCE_PENALTY
	return clampf(multiplier, 0.50, 0.80)


static func adjust_final_surge_chance(
	base_chance: float,
	difficulty_tier: int,
	is_king: bool
) -> float:
	return clampf(
		base_chance * get_final_surge_chance_multiplier(
			difficulty_tier,
			is_king
		),
		0.0,
		1.0
	)


static func adjust_final_surge_stamina_ratio(
	base_ratio: float,
	is_king: bool
) -> float:
	return clampf(
		base_ratio * (
			KING_STAMINA_MULTIPLIER
			if is_king
			else STAMINA_MULTIPLIER
		),
		0.0,
		1.0
	)


static func adjust_final_surge_intensity(
	base_intensity: float,
	is_king: bool
) -> float:
	return maxf(
		base_intensity * (
			KING_INTENSITY_MULTIPLIER
			if is_king
			else INTENSITY_MULTIPLIER
		),
		0.0
	)


static func get_response_label(
	expected_response: StringName,
	fish_lateral: float
) -> String:
	if expected_response == RESPONSE_STEADY:
		return "K + HOLD STRAIGHT"
	if expected_response != RESPONSE_COUNTER:
		return ""
	if fish_lateral > STEERING_DEADZONE:
		return "K + LEFT / HEAD FIRST"
	if fish_lateral < -STEERING_DEADZONE:
		return "K + RIGHT / HEAD FIRST"
	return "K + HOLD STRAIGHT"


static func build_snapshot(
	active: bool,
	window_left: float,
	match_time: float,
	expected_response: StringName,
	last_result: StringName,
	success_count: int,
	fish_lateral: float,
	distance_meters: float,
	mastery_known: bool,
	secured: bool,
	checked: bool
) -> Dictionary:
	return {
		"active": active,
		"label": "LANDING APPROACH",
		"window_left": maxf(window_left, 0.0),
		"match_time": maxf(match_time, 0.0),
		"hold_seconds": RESPONSE_HOLD_SECONDS,
		"expected_response": String(expected_response),
		"response_label": get_response_label(
			expected_response,
			fish_lateral
		),
		"last_result": String(last_result),
		"success_count": maxi(success_count, 0),
		"fish_lateral": clampf(fish_lateral, -1.0, 1.0),
		"distance_meters": maxf(distance_meters, 0.0),
		"mastery_known": mastery_known,
		"secured": secured,
		"checked": checked,
	}
