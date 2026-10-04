extends RefCounted
class_name FishingRunReadingPolicy

## Reading the Run v1 turns the already-authored FishingFightIntent snapshots
## into a small, deterministic response challenge. It does not own fish movement,
## tension, or input; Encounter supplies those existing runtime states.

const RESULT_IDLE: StringName = &"idle"
const RESULT_READING: StringName = &"reading"
const RESULT_SUCCESS: StringName = &"success"
const RESULT_MISSED: StringName = &"missed"
const RESULT_CANCELLED: StringName = &"cancelled"

const RESPONSE_NONE: StringName = &"none"
const RESPONSE_EASE: StringName = &"ease"
const RESPONSE_COUNTER: StringName = &"counter"
const RESPONSE_REEL: StringName = &"reel"
const RESPONSE_STEADY: StringName = &"steady"

const RESPONSE_HOLD_SECONDS: float = 0.12
const MIN_READ_WINDOW_SECONDS: float = 0.35
const MAX_READ_WINDOW_SECONDS: float = 0.70
const READ_WINDOW_DURATION_RATIO: float = 0.45

const MIN_STAMINA_BONUS_RATIO: float = 0.006
const MAX_STAMINA_BONUS_RATIO: float = 0.014


static func get_expected_response(intent: Dictionary) -> StringName:
	if bool(intent.get("thrashing", false)):
		return RESPONSE_EASE

	var intent_id := StringName(str(intent.get("intent_id", "unknown")))
	match intent_id:
		&"surge_away", &"dive":
			return RESPONSE_EASE
		&"side_run":
			return RESPONSE_COUNTER
		&"rise":
			return RESPONSE_REEL
		&"erratic":
			return RESPONSE_STEADY
		_:
			return RESPONSE_NONE


static func get_response_label(response: StringName) -> String:
	match response:
		RESPONSE_EASE:
			return "EASE"
		RESPONSE_COUNTER:
			return "COUNTER"
		RESPONSE_REEL:
			return "REEL"
		RESPONSE_STEADY:
			return "HOLD STEADY"
		_:
			return "NONE"


static func get_read_window_seconds(intent: Dictionary) -> float:
	var duration := maxf(float(intent.get("duration", 0.0)), 0.0)
	if duration <= 0.0:
		return 0.50
	return clampf(
		duration * READ_WINDOW_DURATION_RATIO,
		MIN_READ_WINDOW_SECONDS,
		MAX_READ_WINDOW_SECONDS
	)


static func is_response_matching(
	intent: Dictionary,
	player_reeling: bool,
	player_steering: float,
	steering_deadzone: float = 0.20
) -> bool:
	var expected := get_expected_response(intent)
	var steering_deadzone_abs := maxf(absf(steering_deadzone), 0.01)

	match expected:
		RESPONSE_EASE:
			return not player_reeling

		RESPONSE_REEL:
			return player_reeling

		RESPONSE_COUNTER:
			var fish_lateral := clampf(
				float(intent.get("lateral", 0.0)),
				-1.0,
				1.0
			)
			if absf(fish_lateral) <= steering_deadzone_abs:
				return false
			if absf(player_steering) <= steering_deadzone_abs:
				return false
			return (
				player_reeling
				and signf(player_steering) != signf(fish_lateral)
			)

		RESPONSE_STEADY:
			return (
				player_reeling
				and absf(player_steering) <= steering_deadzone_abs
			)

		_:
			return false


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


static func is_read_complete(match_time: float) -> bool:
	return match_time >= RESPONSE_HOLD_SECONDS


static func get_stamina_control_bonus_ratio(intent: Dictionary) -> float:
	var intensity := clampf(float(intent.get("intensity", 0.0)), 0.0, 1.0)
	return lerpf(
		MIN_STAMINA_BONUS_RATIO,
		MAX_STAMINA_BONUS_RATIO,
		intensity
	)


static func get_result_label(result: StringName) -> String:
	match result:
		RESULT_READING:
			return "reading"
		RESULT_SUCCESS:
			return "success"
		RESULT_MISSED:
			return "missed"
		RESULT_CANCELLED:
			return "cancelled"
		_:
			return "idle"


static func build_snapshot(
	active: bool,
	window_left: float,
	match_time: float,
	expected_response: StringName,
	last_result: StringName,
	success_count: int,
	intent: Dictionary
) -> Dictionary:
	return {
		"active": active,
		"window_left": maxf(window_left, 0.0),
		"match_time": maxf(match_time, 0.0),
		"hold_required": RESPONSE_HOLD_SECONDS,
		"expected_response": expected_response,
		"expected_response_label": get_response_label(expected_response),
		"last_result": last_result,
		"last_result_label": get_result_label(last_result),
		"success_count": maxi(success_count, 0),
		"intent_id": StringName(str(intent.get("intent_id", "unknown"))),
		"intent_label": str(intent.get("label", "UNKNOWN")),
		"thrashing": bool(intent.get("thrashing", false)),
	}
