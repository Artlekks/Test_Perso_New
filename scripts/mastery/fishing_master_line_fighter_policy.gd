extends RefCounted
class_name FishingMasterLineFighterPolicy

## Pure lesson policy for Master Line Fighter.
##
## The lesson observes the existing line-pressure system; it never modifies
## tension, fish stamina, failure thresholds, or authored fish behavior.
## The player demonstrates three pieces of Line Feel during one hooked fish:
## 1. PULL  — recover a light line into working pressure while reeling.
## 2. HOLD  — keep working pressure steady with neutral W/S input.
## 3. YIELD — bring a heavy line safely back down with release/W, without
##            dumping it into slack or allowing it to reach overload.

const BAND_NONE: StringName = &"none"
const BAND_SLACK: StringName = &"slack"
const BAND_LIGHT: StringName = &"light"
const BAND_WORKING: StringName = &"working"
const BAND_HEAVY: StringName = &"heavy"
const BAND_OVERLOAD: StringName = &"overload"

const REQUIRED_HOLD_SECONDS: float = 0.70
const NEUTRAL_BIAS_LIMIT: float = 0.22
const YIELD_BIAS_THRESHOLD: float = -0.15


static func advance_read(
	band: StringName,
	player_reeling: bool,
	tension_bias: float,
	delta: float,
	pull_armed: bool,
	pull_done: bool,
	hold_seconds: float,
	hold_done: bool,
	yield_armed: bool,
	yield_done: bool
) -> Dictionary:
	var next_pull_armed := pull_armed
	var next_pull_done := pull_done
	var next_hold_seconds := maxf(hold_seconds, 0.0)
	var next_hold_done := hold_done
	var next_yield_armed := yield_armed
	var next_yield_done := yield_done

	var pull_completed_now := false
	var hold_completed_now := false
	var yield_completed_now := false
	var unsafe := band == BAND_SLACK or band == BAND_OVERLOAD

	# PULL: first feel a genuinely light line, then take it back into the safe
	# working zone while K is held. Heavy pressure does not count as a clean
	# recovery: the point is to take up line, not blast through the window.
	if not next_pull_done:
		if band == BAND_LIGHT:
			next_pull_armed = true
		elif (
			next_pull_armed
			and band == BAND_WORKING
			and player_reeling
		):
			next_pull_done = true
			next_pull_armed = false
			pull_completed_now = true
		elif unsafe:
			next_pull_armed = false

	# HOLD: demonstrate that working pressure can be maintained instead of
	# constantly pumping the rod. Neutral W/S input is intentional here; K can
	# remain held because the existing backend resolves the actual tension.
	if not next_hold_done:
		var holding_cleanly := (
			band == BAND_WORKING
			and player_reeling
			and absf(tension_bias) <= NEUTRAL_BIAS_LIMIT
		)
		if holding_cleanly:
			next_hold_seconds += maxf(delta, 0.0)
			if next_hold_seconds >= REQUIRED_HOLD_SECONDS:
				next_hold_seconds = REQUIRED_HOLD_SECONDS
				next_hold_done = true
				hold_completed_now = true
		else:
			next_hold_seconds = 0.0

	# YIELD: feel a heavy line first, then deliberately let pressure fall back
	# into LIGHT/WORKING using a reel release or a forward (negative) W/S bias.
	# Falling all the way to slack is an over-yield and must be tried again.
	if not next_yield_done:
		if band == BAND_HEAVY:
			next_yield_armed = true
		elif next_yield_armed and (band == BAND_WORKING or band == BAND_LIGHT):
			var yielding_input := (
				not player_reeling
				or tension_bias <= YIELD_BIAS_THRESHOLD
			)
			if yielding_input:
				next_yield_done = true
				next_yield_armed = false
				yield_completed_now = true
		elif unsafe:
			next_yield_armed = false

	return {
		"pull_armed": next_pull_armed,
		"pull_done": next_pull_done,
		"hold_seconds": next_hold_seconds,
		"hold_done": next_hold_done,
		"yield_armed": next_yield_armed,
		"yield_done": next_yield_done,
		"pull_completed_now": pull_completed_now,
		"hold_completed_now": hold_completed_now,
		"yield_completed_now": yield_completed_now,
		"unsafe": unsafe,
		"complete": is_complete(
			next_pull_done,
			next_hold_done,
			next_yield_done
		),
		"progress": get_progress_ratio(
			next_pull_done,
			next_hold_seconds,
			next_hold_done,
			next_yield_done
		),
	}


static func is_complete(
	pull_done: bool,
	hold_done: bool,
	yield_done: bool
) -> bool:
	return pull_done and hold_done and yield_done


static func get_progress_ratio(
	pull_done: bool,
	hold_seconds: float,
	hold_done: bool,
	yield_done: bool
) -> float:
	var pull_score := 1.0 if pull_done else 0.0
	var hold_score := 1.0 if hold_done else clampf(
		hold_seconds / maxf(REQUIRED_HOLD_SECONDS, 0.001),
		0.0,
		1.0
	)
	var yield_score := 1.0 if yield_done else 0.0
	return (pull_score + hold_score + yield_score) / 3.0
