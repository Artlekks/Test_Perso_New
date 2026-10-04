extends RefCounted
class_name FishingLurePresentationPolicy

## Pure policy for judging how naturally the player is presenting a lure.
##
## This deliberately does not own input or fish state. Bait_V2 publishes the
## player's recent retrieve/pause/twitch/pull pattern and both visible fish and
## the encounter bite roll consume the same multiplier.

const MIN_MULTIPLIER: float = 0.45
const MAX_MULTIPLIER: float = 1.35


static func evaluate(
	motion_style: int,
	retrieve_speed_ratio: float,
	pause_seconds: float,
	twitch_age: float,
	pull_age: float
) -> Dictionary:
	var speed: float = clampf(retrieve_speed_ratio, 0.0, 2.0)
	var pause: float = maxf(pause_seconds, 0.0)
	var twitch_recent: float = _recent_action_strength(twitch_age, 0.70)
	var pull_recent: float = _recent_action_strength(pull_age, 0.70)

	var target_speed: float = 0.50
	var speed_width: float = 0.45
	var pause_bonus: float = 0.0
	var twitch_bonus: float = 0.0
	var pull_bonus: float = 0.0
	var long_pause_penalty: float = 0.0

	match motion_style:
		LureActionProfile.MotionStyle.GLIDE:
			target_speed = 0.35
			speed_width = 0.42
			pause_bonus = 0.10
			twitch_bonus = 0.03
			pull_bonus = 0.05

		LureActionProfile.MotionStyle.BOB:
			target_speed = 0.20
			speed_width = 0.35
			pause_bonus = 0.18
			twitch_bonus = 0.12
			pull_bonus = 0.08

		LureActionProfile.MotionStyle.POP:
			target_speed = 0.24
			speed_width = 0.34
			pause_bonus = 0.14
			twitch_bonus = 0.24
			pull_bonus = 0.18

		LureActionProfile.MotionStyle.SWIM:
			target_speed = 0.58
			speed_width = 0.40
			twitch_bonus = 0.08
			pull_bonus = 0.05
			long_pause_penalty = 0.16

		LureActionProfile.MotionStyle.WOBBLE:
			target_speed = 0.68
			speed_width = 0.42
			twitch_bonus = 0.05
			pull_bonus = 0.04
			long_pause_penalty = 0.18

		LureActionProfile.MotionStyle.SPIN:
			target_speed = 0.78
			speed_width = 0.46
			pull_bonus = 0.03
			long_pause_penalty = 0.24

		LureActionProfile.MotionStyle.SPOON:
			target_speed = 0.50
			speed_width = 0.44
			pause_bonus = 0.06
			twitch_bonus = 0.10
			pull_bonus = 0.10

	var speed_match: float = _triangular_match(
		speed,
		target_speed,
		speed_width
	)
	var useful_pause: float = clampf(pause / 1.15, 0.0, 1.0)
	var excessive_speed: float = clampf((speed - 1.15) / 0.65, 0.0, 1.0)
	var excessive_pause: float = clampf((pause - 1.00) / 1.50, 0.0, 1.0)

	var quality: float = (
		0.62
		+ speed_match * 0.42
		+ useful_pause * pause_bonus
		+ twitch_recent * twitch_bonus
		+ pull_recent * pull_bonus
		- excessive_speed * 0.28
		- excessive_pause * long_pause_penalty
	)

	# Poppers/frogs are deliberately poor when simply burned back without any
	# cadence. Their identity comes from work -> pause -> work, not raw speed.
	if motion_style == LureActionProfile.MotionStyle.POP:
		if speed > 0.70 and twitch_recent < 0.20 and pull_recent < 0.20:
			quality -= 0.18

	# Spinner/wobble action collapses if it is left dead for too long.
	if (
		motion_style == LureActionProfile.MotionStyle.SPIN
		or motion_style == LureActionProfile.MotionStyle.WOBBLE
	):
		if pause > 1.20:
			quality -= 0.12

	var multiplier: float = clampf(
		quality,
		MIN_MULTIPLIER,
		MAX_MULTIPLIER
	)

	return {
		"multiplier": multiplier,
		"quality": inverse_lerp(MIN_MULTIPLIER, MAX_MULTIPLIER, multiplier),
		"label": _quality_label(multiplier),
		"retrieve_speed_ratio": speed,
		"pause_seconds": pause,
		"twitch_recent": twitch_recent,
		"pull_recent": pull_recent,
	}


static func _triangular_match(
	value: float,
	center: float,
	half_width: float
) -> float:
	var width: float = maxf(half_width, 0.01)
	return clampf(
		1.0 - absf(value - center) / width,
		0.0,
		1.0
	)


static func _recent_action_strength(age: float, window: float) -> float:
	if age < 0.0:
		return 0.0
	return 1.0 - clampf(age / maxf(window, 0.01), 0.0, 1.0)


static func _quality_label(multiplier: float) -> String:
	if multiplier >= 1.18:
		return "NATURAL"
	if multiplier >= 0.92:
		return "GOOD"
	if multiplier >= 0.70:
		return "POOR"
	return "UNNATURAL"
