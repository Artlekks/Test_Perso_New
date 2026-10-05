extends RefCounted
class_name FishingMasterWeatherWatcherPolicy

## Teaching policy for Master Weather Watcher.
##
## Weather Sense is observational. The lesson never changes the environment;
## it asks the player to place the lure in the depth band the *existing* active
## weather profile currently favors, then hold that placement continuously.

const REQUIRED_HOLD_SECONDS: float = 1.35
const MIN_TOTAL_DEPTH_METERS: float = 0.30
const SURFACE_MAX_RATIO: float = 0.34
const DEEP_MIN_RATIO: float = 0.66
const EVEN_MIN_RATIO: float = 0.25
const EVEN_MAX_RATIO: float = 0.75
const EVEN_RELATIVE_SPREAD: float = 0.08
const TIE_RELATIVE_MARGIN: float = 0.03


static func get_target_band(
	surface_activity: float,
	mid_activity: float,
	deep_activity: float
) -> StringName:
	var surface := maxf(surface_activity, 0.0)
	var mid := maxf(mid_activity, 0.0)
	var deep := maxf(deep_activity, 0.0)
	var highest := maxf(surface, maxf(mid, deep))
	var lowest := minf(surface, minf(mid, deep))
	if highest <= 0.00001:
		return &"even"
	if highest - lowest <= highest * EVEN_RELATIVE_SPREAD:
		return &"even"

	var contenders := 0
	var contender_floor := highest * (1.0 - TIE_RELATIVE_MARGIN)
	if surface >= contender_floor:
		contenders += 1
	if mid >= contender_floor:
		contenders += 1
	if deep >= contender_floor:
		contenders += 1
	if contenders > 1:
		return &"even"

	if surface >= mid and surface >= deep:
		return &"surface"
	if deep >= surface and deep >= mid:
		return &"deep"
	return &"mid"


static func get_depth_ratio(current_depth: float, total_depth: float) -> float:
	if total_depth < MIN_TOTAL_DEPTH_METERS:
		return 0.0
	return clampf(current_depth / maxf(total_depth, 0.001), 0.0, 1.0)


static func is_target_depth(
	target_band: StringName,
	current_depth: float,
	total_depth: float
) -> bool:
	if total_depth < MIN_TOTAL_DEPTH_METERS:
		return false
	var ratio := get_depth_ratio(current_depth, total_depth)
	match target_band:
		&"surface":
			return ratio <= SURFACE_MAX_RATIO
		&"mid":
			return ratio > SURFACE_MAX_RATIO and ratio < DEEP_MIN_RATIO
		&"deep":
			return ratio >= DEEP_MIN_RATIO
		&"even":
			return ratio >= EVEN_MIN_RATIO and ratio <= EVEN_MAX_RATIO
	return false


static func advance_hold(
	current_hold_seconds: float,
	target_band: StringName,
	current_depth: float,
	total_depth: float,
	delta: float
) -> Dictionary:
	var valid_water := total_depth >= MIN_TOTAL_DEPTH_METERS
	var matching := (
		valid_water
		and is_target_depth(target_band, current_depth, total_depth)
	)
	var hold := maxf(current_hold_seconds, 0.0)
	if matching:
		hold += maxf(delta, 0.0)
	else:
		hold = 0.0
	return {
		"hold_seconds": hold,
		"valid_water": valid_water,
		"matching": matching,
		"depth_ratio": get_depth_ratio(current_depth, total_depth),
		"complete": hold >= REQUIRED_HOLD_SECONDS,
	}


static func get_progress_ratio(hold_seconds: float) -> float:
	return clampf(
		maxf(hold_seconds, 0.0) / maxf(REQUIRED_HOLD_SECONDS, 0.001),
		0.0,
		1.0
	)


static func get_band_label(target_band: StringName) -> String:
	match target_band:
		&"surface":
			return "SURFACE"
		&"mid":
			return "MID-WATER"
		&"deep":
			return "DEEP WATER"
		&"even":
			return "BALANCED MID-COLUMN"
	return "UNKNOWN WATER"
