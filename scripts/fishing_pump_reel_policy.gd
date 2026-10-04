extends RefCounted
class_name FishingPumpReelPolicy

## Pure rules for the optional Pump & Reel technique.
##
## The existing fight controls remain intact:
## - K reels.
## - S performs the existing physical/manual pull.
##
## Pump & Reel adds a skillful cadence on top:
## 1. Release K.
## 2. Tap S while line pressure is controlled.
## 3. Resume K inside a short reel-down window.
##
## A successful cycle gives one extra resisted pull pulse and a small stamina
## bonus. Failed/invalid attempts never remove the old S-pull behavior.

const RESULT_IDLE: StringName = &"idle"
const RESULT_LIFTED: StringName = &"lifted"
const RESULT_SUCCESS: StringName = &"success"
const RESULT_EXPIRED: StringName = &"expired"

const PUMP_REEL_WINDOW_SECONDS: float = 0.65
const PUMP_REEL_COOLDOWN_SECONDS: float = 0.35

const MIN_START_SAFE_RATIO: float = 0.08
const MAX_START_SAFE_RATIO: float = 0.72

const MIN_LIFT_TENSION_IMPULSE: float = 0.025
const MAX_LIFT_TENSION_IMPULSE: float = 0.060

const MIN_STAMINA_BONUS_RATIO: float = 0.012
const MAX_STAMINA_BONUS_RATIO: float = 0.035


static func get_start_block_reason(
	player_reeling: bool,
	pressure_band: StringName,
	safe_ratio: float,
	thrashing: bool,
	cooldown_left: float
) -> StringName:
	if cooldown_left > 0.0:
		return &"cooldown"
	if player_reeling:
		return &"release_reel_first"
	if thrashing:
		return &"fish_thrashing"
	if pressure_band == &"slack":
		return &"line_slack"
	if pressure_band == &"overload":
		return &"line_overload"
	if pressure_band == &"heavy":
		return &"pressure_too_high"

	var ratio := clampf(safe_ratio, 0.0, 1.0)
	if ratio < MIN_START_SAFE_RATIO:
		return &"pressure_too_low"
	if ratio > MAX_START_SAFE_RATIO:
		return &"pressure_too_high"

	return &""


static func can_start(
	player_reeling: bool,
	pressure_band: StringName,
	safe_ratio: float,
	thrashing: bool,
	cooldown_left: float
) -> bool:
	return get_start_block_reason(
		player_reeling,
		pressure_band,
		safe_ratio,
		thrashing,
		cooldown_left
	) == &""


static func get_lift_tension_impulse(safe_ratio: float) -> float:
	# Light pressure gets a slightly stronger lift so the line stays taut while
	# K is released. Near the heavy edge, the lift is intentionally smaller.
	var ratio := clampf(safe_ratio, 0.0, 1.0)
	var normalized := clampf(
		inverse_lerp(MIN_START_SAFE_RATIO, MAX_START_SAFE_RATIO, ratio),
		0.0,
		1.0
	)
	return lerpf(
		MAX_LIFT_TENSION_IMPULSE,
		MIN_LIFT_TENSION_IMPULSE,
		normalized
	)


static func get_stamina_bonus_ratio(safe_ratio: float) -> float:
	# Best leverage is around the working middle of the safe band. A valid pump
	# at the edges still helps, but less than a well-timed controlled lift.
	var ratio := clampf(safe_ratio, 0.0, 1.0)
	var distance_from_working := absf(ratio - 0.52)
	var quality := clampf(1.0 - distance_from_working / 0.52, 0.0, 1.0)
	return lerpf(
		MIN_STAMINA_BONUS_RATIO,
		MAX_STAMINA_BONUS_RATIO,
		quality
	)


static func build_snapshot(
	active: bool,
	window_left: float,
	cooldown_left: float,
	last_result: StringName,
	success_count: int,
	safe_ratio: float
) -> Dictionary:
	return {
		"active": active,
		"window_left": maxf(window_left, 0.0),
		"window_total": PUMP_REEL_WINDOW_SECONDS,
		"cooldown_left": maxf(cooldown_left, 0.0),
		"last_result": last_result,
		"success_count": maxi(success_count, 0),
		"safe_ratio": clampf(safe_ratio, 0.0, 1.0),
	}
