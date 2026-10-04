extends RefCounted
class_name FishingFightPressurePolicy

## Converts the existing tension gauge into meaningful line-pressure leverage.
##
## The underlying failure rules stay owned by FishingTension:
## - too little tension can throw the hook;
## - too much tension can break the line.
##
## Inside the SAFE range, however, pressure is no longer binary. Working near
## the high side tires the fish faster, while light pressure gives the fish more
## time to recover. This makes W/S pressure management a real decision without
## changing authored line-break or hook-off thresholds.

const BAND_NONE: StringName = &"none"
const BAND_SLACK: StringName = &"slack"
const BAND_LIGHT: StringName = &"light"
const BAND_WORKING: StringName = &"working"
const BAND_HEAVY: StringName = &"heavy"
const BAND_OVERLOAD: StringName = &"overload"

const LIGHT_FATIGUE_MULTIPLIER: float = 0.70
const HEAVY_FATIGUE_MULTIPLIER: float = 1.30


static func get_safe_ratio(
	tension_value: float,
	safe_min: float,
	safe_max: float
) -> float:
	if safe_max <= safe_min:
		return 0.5
	return clampf(
		inverse_lerp(safe_min, safe_max, tension_value),
		0.0,
		1.0
	)


static func get_band(
	tension_value: float,
	safe_min: float,
	safe_max: float
) -> StringName:
	if tension_value < safe_min:
		return BAND_SLACK
	if tension_value > safe_max:
		return BAND_OVERLOAD

	var ratio := get_safe_ratio(tension_value, safe_min, safe_max)
	if ratio < 0.34:
		return BAND_LIGHT
	if ratio < 0.72:
		return BAND_WORKING
	return BAND_HEAVY


static func get_fatigue_multiplier(
	tension_value: float,
	safe_min: float,
	safe_max: float
) -> float:
	if tension_value < safe_min or tension_value > safe_max:
		return 0.0

	var ratio := get_safe_ratio(tension_value, safe_min, safe_max)
	return lerpf(
		LIGHT_FATIGUE_MULTIPLIER,
		HEAVY_FATIGUE_MULTIPLIER,
		ratio
	)


static func build_snapshot(
	tension_value: float,
	safe_min: float,
	safe_max: float
) -> Dictionary:
	return {
		"band": get_band(tension_value, safe_min, safe_max),
		"safe_ratio": get_safe_ratio(tension_value, safe_min, safe_max),
		"fatigue_multiplier": get_fatigue_multiplier(
			tension_value,
			safe_min,
			safe_max
		),
		"tension": clampf(tension_value, 0.0, 1.0),
		"safe_min": safe_min,
		"safe_max": safe_max,
	}
