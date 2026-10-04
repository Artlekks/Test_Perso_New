extends RefCounted
class_name FishingSurfaceControlPolicy

## Surface Control v1
##
## Near the surface, a fish has less water above it and its runs, rises and
## head-shakes become abrupt. The surface instability itself is baseline fight
## behavior and exists whether or not the mastery is known. A trained angler
## can stabilize that moment by keeping the rod low while preserving the
## ordinary Reading-the-Run response.
##
## This is intentionally distinct from Aerial Fish Control: aerial control owns
## actual breaches/jumps. Surface Control owns fish that are still in the water
## but fighting in the top layer. It is also distinct from Landing Technique,
## which will own the final approach after the fish is already beaten.

const RESULT_IDLE: StringName = &"idle"
const RESULT_READING: StringName = &"reading"
const RESULT_UNCONTROLLED: StringName = &"uncontrolled_surface"
const RESULT_SUCCESS: StringName = &"success"
const RESULT_MISSED: StringName = &"missed"
const RESULT_CANCELLED: StringName = &"cancelled"

const RESPONSE_NONE: StringName = &"none"
const RESPONSE_LOW_EASE: StringName = &"low_rod_ease"
const RESPONSE_LOW_COUNTER: StringName = &"low_rod_counter"
const RESPONSE_LOW_REEL: StringName = &"low_rod_reel"
const RESPONSE_LOW_STEADY: StringName = &"low_rod_steady"

const MAX_SURFACE_DEPTH_METERS: float = 0.85
const MAX_SURFACE_DEPTH_RATIO: float = 0.24
const MIN_EVENT_INTENSITY: float = 0.45
const ROD_LOW_DEADZONE: float = 0.28
const STEERING_DEADZONE: float = 0.20

const RESPONSE_HOLD_SECONDS: float = 0.14
const WINDOW_MIN_SECONDS: float = 0.42
const WINDOW_MAX_SECONDS: float = 0.68
const EVENT_COOLDOWN_SECONDS: float = 1.10

const INSTABILITY_IMPULSE_MIN: float = 0.025
const INSTABILITY_IMPULSE_MAX: float = 0.060
const RELIEF_IMPULSE_MIN: float = 0.020
const RELIEF_IMPULSE_MAX: float = 0.045
const STAMINA_BONUS_MIN: float = 0.006
const STAMINA_BONUS_MAX: float = 0.014


static func get_depth_ratio(
	current_depth_m: float,
	total_depth_m: float
) -> float:
	if total_depth_m <= 0.001:
		return 0.0
	return clampf(current_depth_m / total_depth_m, 0.0, 1.0)


static func is_near_surface(
	current_depth_m: float,
	total_depth_m: float
) -> bool:
	var depth := maxf(current_depth_m, 0.0)
	if depth <= MAX_SURFACE_DEPTH_METERS:
		return true
	if total_depth_m <= 0.001:
		return false
	return get_depth_ratio(depth, total_depth_m) <= MAX_SURFACE_DEPTH_RATIO


static func get_expected_response(intent: Dictionary) -> StringName:
	if bool(intent.get("thrashing", false)):
		return RESPONSE_LOW_EASE

	var intent_id := StringName(str(intent.get("intent_id", "unknown")))
	match intent_id:
		&"surge_away":
			return RESPONSE_LOW_EASE
		&"side_run":
			return RESPONSE_LOW_COUNTER
		&"rise":
			return RESPONSE_LOW_REEL
		&"erratic":
			return RESPONSE_LOW_STEADY
		_:
			return RESPONSE_NONE


static func should_start(
	intent: Dictionary,
	current_depth_m: float,
	total_depth_m: float,
	cooldown_left: float = 0.0
) -> bool:
	if cooldown_left > 0.0:
		return false
	if get_expected_response(intent) == RESPONSE_NONE:
		return false
	if float(intent.get("intensity", 0.0)) < MIN_EVENT_INTENSITY:
		return false
	return is_near_surface(current_depth_m, total_depth_m)


static func get_window_seconds(intent: Dictionary) -> float:
	var intensity := clampf(float(intent.get("intensity", 0.0)), 0.0, 1.0)
	## Violent surface behavior is readable, but the correction window is tighter.
	return lerpf(WINDOW_MAX_SECONDS, WINDOW_MIN_SECONDS, intensity)


static func is_response_matching(
	expected_response: StringName,
	intent: Dictionary,
	player_reeling: bool,
	player_steering: float,
	player_tension_bias: float
) -> bool:
	var rod_is_low := player_tension_bias <= -ROD_LOW_DEADZONE
	if not rod_is_low:
		return false

	match expected_response:
		RESPONSE_LOW_EASE:
			return not player_reeling

		RESPONSE_LOW_REEL:
			return player_reeling

		RESPONSE_LOW_COUNTER:
			var fish_lateral := clampf(
				float(intent.get("lateral", 0.0)),
				-1.0,
				1.0
			)
			if absf(fish_lateral) <= STEERING_DEADZONE:
				return false
			if absf(player_steering) <= STEERING_DEADZONE:
				return false
			return (
				player_reeling
				and signf(player_steering) != signf(fish_lateral)
			)

		RESPONSE_LOW_STEADY:
			return (
				player_reeling
				and absf(player_steering) <= STEERING_DEADZONE
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


static func is_response_complete(match_time: float) -> bool:
	return match_time >= RESPONSE_HOLD_SECONDS


static func get_surface_instability_impulse(
	intent: Dictionary,
	current_depth_m: float,
	total_depth_m: float
) -> float:
	var intensity := clampf(float(intent.get("intensity", 0.0)), 0.0, 1.0)
	var pressure := clampf(float(intent.get("pressure", 0.0)), 0.0, 1.0)
	var depth_ratio := get_depth_ratio(current_depth_m, total_depth_m)
	var surface_factor := 1.0 - clampf(
		depth_ratio / maxf(MAX_SURFACE_DEPTH_RATIO, 0.01),
		0.0,
		1.0
	)
	var severity := clampf(
		intensity * 0.55
		+ pressure * 0.25
		+ surface_factor * 0.20,
		0.0,
		1.0
	)
	return lerpf(
		INSTABILITY_IMPULSE_MIN,
		INSTABILITY_IMPULSE_MAX,
		severity
	)


static func get_success_relief_impulse(
	instability_impulse: float,
	intent: Dictionary
) -> float:
	var intensity := clampf(float(intent.get("intensity", 0.0)), 0.0, 1.0)
	var relief := lerpf(
		RELIEF_IMPULSE_MIN,
		RELIEF_IMPULSE_MAX,
		intensity
	)
	## Good surface control absorbs most of the abrupt load, but never deletes
	## the surface behavior completely.
	return -minf(relief, maxf(instability_impulse, 0.0) * 0.72)


static func get_stamina_bonus_ratio(intent: Dictionary) -> float:
	var intensity := clampf(float(intent.get("intensity", 0.0)), 0.0, 1.0)
	return lerpf(STAMINA_BONUS_MIN, STAMINA_BONUS_MAX, intensity)


static func get_response_label(response: StringName) -> String:
	match response:
		RESPONSE_LOW_EASE:
			return "RELEASE K + W / LOW ROD"
		RESPONSE_LOW_COUNTER:
			return "K + W + COUNTER A/D"
		RESPONSE_LOW_REEL:
			return "K + W / LOW ROD"
		RESPONSE_LOW_STEADY:
			return "K + W / HOLD STEADY"
		_:
			return "NONE"


static func get_result_label(result: StringName) -> String:
	match result:
		RESULT_READING:
			return "reading"
		RESULT_UNCONTROLLED:
			return "uncontrolled surface"
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
	intent: Dictionary,
	mastery_known: bool,
	current_depth_m: float,
	total_depth_m: float,
	instability_impulse: float,
	cooldown_left: float
) -> Dictionary:
	return {
		"active": active,
		"window_left": maxf(window_left, 0.0),
		"match_time": maxf(match_time, 0.0),
		"hold_required": RESPONSE_HOLD_SECONDS,
		"expected_response": expected_response if active else RESPONSE_NONE,
		"expected_response_label": (
			get_response_label(expected_response)
			if active
			else "NONE"
		),
		"last_result": last_result,
		"last_result_label": get_result_label(last_result),
		"success_count": maxi(success_count, 0),
		"mastery_known": mastery_known,
		"near_surface": is_near_surface(current_depth_m, total_depth_m),
		"current_depth_m": maxf(current_depth_m, 0.0),
		"total_depth_m": maxf(total_depth_m, 0.0),
		"depth_ratio": get_depth_ratio(current_depth_m, total_depth_m),
		"instability_impulse": maxf(instability_impulse, 0.0),
		"cooldown_left": maxf(cooldown_left, 0.0),
		"intent_id": StringName(str(intent.get("intent_id", "unknown"))),
		"intent_label": str(intent.get("label", "UNKNOWN")),
		"thrashing": bool(intent.get("thrashing", false)),
	}
