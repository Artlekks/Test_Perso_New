extends RefCounted
class_name FishingAerialControlPolicy

## Aerial Fish Control v1
##
## A normal RISE remains a Reading-the-Run event. Only some rise intents become
## a breach. Breach frequency comes from the already-authored rise tendency,
## vertical activity and archetype, while the correct response also considers
## tackle hook security. This keeps the mechanic species/tackle-specific instead
## of turning every surface jump into the same release-K rule.

const RESULT_IDLE: StringName = &"idle"
const RESULT_READING: StringName = &"reading"
const RESULT_SUCCESS: StringName = &"success"
const RESULT_MISSED: StringName = &"missed"
const RESULT_CANCELLED: StringName = &"cancelled"

const RESPONSE_NONE: StringName = &"none"
const RESPONSE_BOW_LOW: StringName = &"bow_low"
const RESPONSE_HIGH_FOLLOW: StringName = &"high_follow"

const RESPONSE_HOLD_SECONDS: float = 0.14
const MIN_WINDOW_SECONDS: float = 0.46
const MAX_WINDOW_SECONDS: float = 0.78
const WINDOW_DURATION_RATIO: float = 0.55
const EVENT_COOLDOWN_SECONDS: float = 2.25
const ROD_BIAS_DEADZONE: float = 0.28
const MAX_BREACH_CHANCE: float = 0.78

const AUTO_RISK_THRESHOLD: float = 0.32
const HOOK_SECURITY_LOW: float = 0.85
const HOOK_SECURITY_HIGH: float = 1.30
const HOOK_SECURITY_RELIEF_MAX: float = 0.24

const BOW_FAIL_IMPULSE_MIN: float = 0.09
const BOW_FAIL_IMPULSE_MAX: float = 0.15
const FOLLOW_FAIL_IMPULSE_MIN: float = -0.11
const FOLLOW_FAIL_IMPULSE_MAX: float = -0.07
const SUCCESS_STABILIZE_MIN: float = 0.018
const SUCCESS_STABILIZE_MAX: float = 0.038


static func is_rise_intent(intent: Dictionary) -> bool:
	if bool(intent.get("thrashing", false)):
		return false
	return StringName(str(intent.get("intent_id", "unknown"))) == &"rise"


static func get_rise_share(profile: FishBehaviorProfile) -> float:
	if profile == null:
		return 0.0
	var total := maxf(profile.get_total_action_weight(), 0.001)
	return clampf(maxf(profile.rise_weight, 0.0) / total, 0.0, 1.0)


static func get_breach_chance(profile: FishBehaviorProfile) -> float:
	if profile == null:
		return 0.0
	if profile.aerial_control_style == FishBehaviorProfile.AerialControlStyle.DISABLED:
		return 0.0
	if profile.vertical_activity < 0.55:
		return 0.0

	var rise_share := get_rise_share(profile)
	if rise_share < 0.075:
		return 0.0

	var chance := 0.04
	chance += rise_share * 0.78
	chance += clampf(profile.vertical_activity, 0.0, 1.0) * 0.12

	match profile.archetype:
		FishBehaviorProfile.FightArchetype.DARTING:
			chance += 0.08
		FishBehaviorProfile.FightArchetype.AGGRESSIVE:
			chance += 0.02
		FishBehaviorProfile.FightArchetype.HEAVY:
			chance -= 0.15
		FishBehaviorProfile.FightArchetype.ERRATIC:
			chance -= 0.05

	chance *= maxf(profile.aerial_frequency_multiplier, 0.0)
	return clampf(chance, 0.0, MAX_BREACH_CHANCE)


static func should_start(
	intent: Dictionary,
	profile: FishBehaviorProfile,
	roll: float,
	cooldown_left: float,
	visual_profile_allowed: bool = true
) -> bool:
	if cooldown_left > 0.0 or not visual_profile_allowed:
		return false
	if not is_rise_intent(intent):
		return false
	var chance := get_breach_chance(profile)
	if chance <= 0.0:
		return false
	return clampf(roll, 0.0, 1.0) <= chance


static func get_expected_response(
	profile: FishBehaviorProfile,
	hook_security: float
) -> StringName:
	if profile == null:
		return RESPONSE_NONE

	match profile.aerial_control_style:
		FishBehaviorProfile.AerialControlStyle.BOW_LOW:
			return RESPONSE_BOW_LOW
		FishBehaviorProfile.AerialControlStyle.HIGH_FOLLOW:
			return RESPONSE_HIGH_FOLLOW
		FishBehaviorProfile.AerialControlStyle.DISABLED:
			return RESPONSE_NONE

	var risk := get_rise_share(profile) * 0.65
	risk += clampf(profile.vertical_activity, 0.0, 1.0) * 0.25

	match profile.archetype:
		FishBehaviorProfile.FightArchetype.DARTING:
			risk += 0.18
		FishBehaviorProfile.FightArchetype.ERRATIC:
			risk += 0.08
		FishBehaviorProfile.FightArchetype.STEADY:
			risk += 0.02
		FishBehaviorProfile.FightArchetype.AGGRESSIVE:
			risk -= 0.07
		FishBehaviorProfile.FightArchetype.HEAVY:
			risk -= 0.18

	var security_ratio := inverse_lerp(
		HOOK_SECURITY_LOW,
		HOOK_SECURITY_HIGH,
		clampf(hook_security, HOOK_SECURITY_LOW, HOOK_SECURITY_HIGH)
	)
	risk -= security_ratio * HOOK_SECURITY_RELIEF_MAX

	if risk >= AUTO_RISK_THRESHOLD:
		return RESPONSE_BOW_LOW
	return RESPONSE_HIGH_FOLLOW


static func get_response_label(response: StringName) -> String:
	match response:
		RESPONSE_BOW_LOW:
			return "BOW / LOW ROD"
		RESPONSE_HIGH_FOLLOW:
			return "HIGH ROD / FOLLOW"
		_:
			return "NONE"


static func get_window_seconds(intent: Dictionary) -> float:
	var duration := maxf(float(intent.get("duration", 0.0)), 0.0)
	if duration <= 0.0:
		return 0.60
	return clampf(
		duration * WINDOW_DURATION_RATIO,
		MIN_WINDOW_SECONDS,
		MAX_WINDOW_SECONDS
	)


static func is_response_matching(
	response: StringName,
	player_reeling: bool,
	player_tension_bias: float
) -> bool:
	match response:
		RESPONSE_BOW_LOW:
			return (
				not player_reeling
				and player_tension_bias <= -ROD_BIAS_DEADZONE
			)
		RESPONSE_HIGH_FOLLOW:
			return (
				player_reeling
				and player_tension_bias >= ROD_BIAS_DEADZONE
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


static func get_failure_tension_impulse(
	response: StringName,
	intensity: float,
	hook_security: float
) -> float:
	var t := clampf(intensity, 0.0, 1.0)
	var security_scale := clampf(
		1.0 / maxf(hook_security, 0.65),
		0.72,
		1.25
	)

	match response:
		RESPONSE_BOW_LOW:
			return lerpf(
				BOW_FAIL_IMPULSE_MIN,
				BOW_FAIL_IMPULSE_MAX,
				t
			) * security_scale
		RESPONSE_HIGH_FOLLOW:
			return lerpf(
				FOLLOW_FAIL_IMPULSE_MAX,
				FOLLOW_FAIL_IMPULSE_MIN,
				t
			) * security_scale
		_:
			return 0.0


static func get_success_stabilization_impulse(
	response: StringName,
	intensity: float
) -> float:
	var amount := lerpf(
		SUCCESS_STABILIZE_MIN,
		SUCCESS_STABILIZE_MAX,
		clampf(intensity, 0.0, 1.0)
	)
	match response:
		RESPONSE_BOW_LOW:
			# Releasing K + lowering the rod is intentionally slack-biased. A tiny
			# positive correction keeps the taught response from becoming a trap.
			return amount
		RESPONSE_HIGH_FOLLOW:
			# High rod + K is intentionally pressure-biased. Mirror the correction.
			return -amount
		_:
			return 0.0


static func build_snapshot(
	active: bool,
	window_left: float,
	match_time: float,
	expected_response: StringName,
	last_result: StringName,
	success_count: int,
	intent: Dictionary,
	profile: FishBehaviorProfile,
	hook_security: float,
	cooldown_left: float
) -> Dictionary:
	return {
		"active": active,
		"window_left": maxf(window_left, 0.0),
		"match_time": maxf(match_time, 0.0),
		"hold_required": RESPONSE_HOLD_SECONDS,
		"expected_response": expected_response,
		"expected_response_label": get_response_label(expected_response),
		"last_result": last_result,
		"success_count": maxi(success_count, 0),
		"intent_id": StringName(str(intent.get("intent_id", "unknown"))),
		"intent_label": str(intent.get("label", "UNKNOWN")),
		"intensity": clampf(float(intent.get("intensity", 0.0)), 0.0, 1.0),
		"personality": (
			profile.get_personality_label()
			if profile != null
			else "UNPROFILED"
		),
		"breach_chance": get_breach_chance(profile),
		"hook_security": maxf(hook_security, 0.0),
		"cooldown_left": maxf(cooldown_left, 0.0),
	}
