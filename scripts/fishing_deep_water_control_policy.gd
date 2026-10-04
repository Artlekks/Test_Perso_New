extends RefCounted
class_name FishingDeepWaterControlPolicy

## Deep-Water Control v1
##
## A powerful DIVE in genuinely deep water creates a delayed vertical load. The
## ordinary Reading-the-Run response still owns the first beat: ease off and let
## the fish descend. Deep-Water Control owns the second beat: once the delayed
## load arrives, a trained angler can recover contact with K + S (high rod).
##
## The deep-water load is world/fight behavior and exists whether or not the
## mastery is known. Learning the mastery does not remove the challenge; it
## unlocks a deterministic way to recover part of the load and turn the vertical
## fight into a small stamina advantage.

const RESULT_IDLE: StringName = &"idle"
const RESULT_FOLLOWING: StringName = &"following"
const RESULT_RECOVERING: StringName = &"recovering"
const RESULT_UNCONTROLLED: StringName = &"uncontrolled_load"
const RESULT_SUCCESS: StringName = &"success"
const RESULT_MISSED: StringName = &"missed"
const RESULT_CANCELLED: StringName = &"cancelled"

const PHASE_NONE: StringName = &"none"
const PHASE_FOLLOW: StringName = &"follow"
const PHASE_RECOVER: StringName = &"recover"

const RESPONSE_NONE: StringName = &"none"
const RESPONSE_HIGH_ROD: StringName = &"high_rod_recover"

const MIN_TOTAL_DEPTH_METERS: float = 2.50
const MIN_DIVE_INTENSITY: float = 0.52
const MIN_EFFECTIVE_DEPTH_RATIO: float = 0.50
const MIN_DIVE_DEPTH_COMMITMENT: float = 0.42

const FOLLOW_DELAY_MIN_SECONDS: float = 0.30
const FOLLOW_DELAY_MAX_SECONDS: float = 0.52
const RECOVERY_WINDOW_MIN_SECONDS: float = 0.46
const RECOVERY_WINDOW_MAX_SECONDS: float = 0.72
const RECOVERY_HOLD_SECONDS: float = 0.16
const EVENT_COOLDOWN_SECONDS: float = 1.35
const ROD_BIAS_DEADZONE: float = 0.28

const LOAD_IMPULSE_MIN: float = 0.075
const LOAD_IMPULSE_MAX: float = 0.155
const RECOVERY_RELIEF_MIN: float = 0.030
const RECOVERY_RELIEF_MAX: float = 0.060
const STAMINA_BONUS_MIN: float = 0.008
const STAMINA_BONUS_MAX: float = 0.018


static func is_dive_intent(intent: Dictionary) -> bool:
	if bool(intent.get("thrashing", false)):
		return false
	return StringName(str(intent.get("intent_id", "unknown"))) == &"dive"


static func get_dive_commitment(intent: Dictionary) -> float:
	if not is_dive_intent(intent):
		return 0.0
	return clampf(-float(intent.get("depth", 0.0)), 0.0, 1.0)


static func get_bait_depth_ratio(
	current_depth_m: float,
	total_depth_m: float
) -> float:
	if total_depth_m <= 0.001:
		return 0.0
	return clampf(current_depth_m / total_depth_m, 0.0, 1.0)


static func get_effective_depth_ratio(
	current_depth_m: float,
	total_depth_m: float,
	intent: Dictionary
) -> float:
	## At intent start the hooked bait may not yet have physically reached the
	## fish's target depth. Blend the real bait depth with the authored downward
	## commitment so the delayed load can begin while the fish is actually diving
	## rather than one frame after the lure catches up.
	var physical_ratio := get_bait_depth_ratio(current_depth_m, total_depth_m)
	var dive_commitment := get_dive_commitment(intent)
	var intent_ratio := dive_commitment * 0.78
	return clampf(maxf(physical_ratio, intent_ratio), 0.0, 1.0)


static func should_start(
	intent: Dictionary,
	current_depth_m: float,
	total_depth_m: float,
	cooldown_left: float = 0.0
) -> bool:
	if cooldown_left > 0.0:
		return false
	if not is_dive_intent(intent):
		return false
	if total_depth_m < MIN_TOTAL_DEPTH_METERS:
		return false
	if float(intent.get("intensity", 0.0)) < MIN_DIVE_INTENSITY:
		return false
	if get_dive_commitment(intent) < MIN_DIVE_DEPTH_COMMITMENT:
		return false
	return (
		get_effective_depth_ratio(current_depth_m, total_depth_m, intent)
		>= MIN_EFFECTIVE_DEPTH_RATIO
	)


static func get_follow_delay_seconds(intent: Dictionary) -> float:
	var intensity := clampf(float(intent.get("intensity", 0.0)), 0.0, 1.0)
	## Harder dives load the line sooner.
	return lerpf(
		FOLLOW_DELAY_MAX_SECONDS,
		FOLLOW_DELAY_MIN_SECONDS,
		intensity
	)


static func get_recovery_window_seconds(intent: Dictionary) -> float:
	var intensity := clampf(float(intent.get("intensity", 0.0)), 0.0, 1.0)
	## Powerful deep fish give a slightly tighter second beat.
	return lerpf(
		RECOVERY_WINDOW_MAX_SECONDS,
		RECOVERY_WINDOW_MIN_SECONDS,
		intensity
	)


static func get_delayed_load_impulse(
	intent: Dictionary,
	current_depth_m: float,
	total_depth_m: float
) -> float:
	var intensity := clampf(float(intent.get("intensity", 0.0)), 0.0, 1.0)
	var pressure := clampf(float(intent.get("pressure", 0.0)), 0.0, 1.0)
	var depth_ratio := get_effective_depth_ratio(
		current_depth_m,
		total_depth_m,
		intent
	)
	var water_depth_factor := clampf(
		inverse_lerp(MIN_TOTAL_DEPTH_METERS, 8.0, total_depth_m),
		0.0,
		1.0
	)
	var severity := clampf(
		intensity * 0.45
		+ pressure * 0.20
		+ depth_ratio * 0.25
		+ water_depth_factor * 0.10,
		0.0,
		1.0
	)
	return lerpf(LOAD_IMPULSE_MIN, LOAD_IMPULSE_MAX, severity)


static func is_recovery_response_matching(
	player_reeling: bool,
	player_tension_bias: float
) -> bool:
	return (
		player_reeling
		and player_tension_bias >= ROD_BIAS_DEADZONE
	)


static func advance_match_time(
	current_time: float,
	is_matching: bool,
	delta: float
) -> float:
	if not is_matching:
		return 0.0
	return minf(
		maxf(current_time, 0.0) + maxf(delta, 0.0),
		RECOVERY_HOLD_SECONDS
	)


static func is_recovery_complete(match_time: float) -> bool:
	return match_time >= RECOVERY_HOLD_SECONDS


static func get_success_relief_impulse(
	load_impulse: float,
	intent: Dictionary
) -> float:
	var intensity := clampf(float(intent.get("intensity", 0.0)), 0.0, 1.0)
	var relief := lerpf(
		RECOVERY_RELIEF_MIN,
		RECOVERY_RELIEF_MAX,
		intensity
	)
	## Never erase the entire deep-water load. Mastery means controlling the load,
	## not making deep water mechanically identical to shallow water.
	return -minf(relief, maxf(load_impulse, 0.0) * 0.62)


static func get_stamina_bonus_ratio(intent: Dictionary) -> float:
	var intensity := clampf(float(intent.get("intensity", 0.0)), 0.0, 1.0)
	return lerpf(STAMINA_BONUS_MIN, STAMINA_BONUS_MAX, intensity)


static func get_response_label(response: StringName) -> String:
	match response:
		RESPONSE_HIGH_ROD:
			return "K + S / HIGH ROD"
		_:
			return "NONE"


static func get_phase_label(phase: StringName) -> String:
	match phase:
		PHASE_FOLLOW:
			return "FOLLOW THE DIVE"
		PHASE_RECOVER:
			return "RECOVER THE LOAD"
		_:
			return "NONE"


static func get_result_label(result: StringName) -> String:
	match result:
		RESULT_FOLLOWING:
			return "following"
		RESULT_RECOVERING:
			return "recovering"
		RESULT_UNCONTROLLED:
			return "uncontrolled load"
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
	phase: StringName,
	delay_left: float,
	window_left: float,
	match_time: float,
	last_result: StringName,
	success_count: int,
	intent: Dictionary,
	mastery_known: bool,
	current_depth_m: float,
	total_depth_m: float,
	load_impulse: float,
	cooldown_left: float
) -> Dictionary:
	var expected_response := (
		RESPONSE_HIGH_ROD
		if active and phase == PHASE_RECOVER and mastery_known
		else RESPONSE_NONE
	)
	return {
		"active": active,
		"phase": phase,
		"phase_label": get_phase_label(phase),
		"delay_left": maxf(delay_left, 0.0),
		"window_left": maxf(window_left, 0.0),
		"match_time": maxf(match_time, 0.0),
		"hold_required": RECOVERY_HOLD_SECONDS,
		"expected_response": expected_response,
		"expected_response_label": get_response_label(expected_response),
		"last_result": last_result,
		"last_result_label": get_result_label(last_result),
		"success_count": maxi(success_count, 0),
		"mastery_known": mastery_known,
		"intent_id": StringName(str(intent.get("intent_id", "unknown"))),
		"intent_label": str(intent.get("label", "UNKNOWN")),
		"intensity": clampf(float(intent.get("intensity", 0.0)), 0.0, 1.0),
		"current_depth_m": maxf(current_depth_m, 0.0),
		"total_depth_m": maxf(total_depth_m, 0.0),
		"depth_ratio": get_effective_depth_ratio(
			current_depth_m,
			total_depth_m,
			intent
		),
		"load_impulse": maxf(load_impulse, 0.0),
		"cooldown_left": maxf(cooldown_left, 0.0),
	}
