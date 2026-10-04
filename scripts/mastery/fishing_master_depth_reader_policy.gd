extends RefCounted
class_name FishingMasterDepthReaderPolicy

## Depth Reader is an observation lesson. The player demonstrates that they can
## follow the lure through the local water column without using the reel to fake
## the transition between depth bands.

const MIN_TOTAL_DEPTH_METERS: float = 0.30
const REQUIRED_OBSERVATION_SECONDS: float = 1.20
const SHALLOW_MAX_RATIO: float = 0.34
const DEEP_MIN_RATIO: float = 0.66


static func get_depth_ratio(current_depth: float, total_depth: float) -> float:
	if total_depth < MIN_TOTAL_DEPTH_METERS:
		return 0.0
	return clampf(current_depth / maxf(total_depth, 0.001), 0.0, 1.0)


static func get_depth_band(current_depth: float, total_depth: float) -> StringName:
	if total_depth < MIN_TOTAL_DEPTH_METERS:
		return &"invalid"
	var ratio := get_depth_ratio(current_depth, total_depth)
	if ratio <= SHALLOW_MAX_RATIO:
		return &"shallow"
	if ratio >= DEEP_MIN_RATIO:
		return &"deep"
	return &"mid"


static func advance_observation(
	observation_seconds: float,
	seen_shallow: bool,
	seen_mid: bool,
	seen_deep: bool,
	current_depth: float,
	total_depth: float,
	is_reeling: bool,
	delta: float
) -> Dictionary:
	var elapsed := maxf(observation_seconds, 0.0)
	var shallow := seen_shallow
	var mid := seen_mid
	var deep := seen_deep
	var valid_water := total_depth >= MIN_TOTAL_DEPTH_METERS
	var band := get_depth_band(current_depth, total_depth)

	if valid_water and not is_reeling:
		elapsed += maxf(delta, 0.0)
		match band:
			&"shallow":
				shallow = true
			&"mid":
				mid = true
			&"deep":
				deep = true

	return {
		"observation_seconds": elapsed,
		"seen_shallow": shallow,
		"seen_mid": mid,
		"seen_deep": deep,
		"current_depth": maxf(current_depth, 0.0),
		"total_depth": maxf(total_depth, 0.0),
		"depth_ratio": get_depth_ratio(current_depth, total_depth),
		"depth_band": band,
		"valid_water": valid_water,
		"reeling": is_reeling,
		"complete": is_complete(elapsed, shallow, mid, deep),
	}


static func is_complete(
	observation_seconds: float,
	seen_shallow: bool,
	seen_mid: bool,
	seen_deep: bool
) -> bool:
	return (
		observation_seconds >= REQUIRED_OBSERVATION_SECONDS
		and seen_shallow
		and seen_mid
		and seen_deep
	)


static func get_progress_ratio(
	observation_seconds: float,
	seen_shallow: bool,
	seen_mid: bool,
	seen_deep: bool
) -> float:
	var time_ratio := clampf(
		observation_seconds / maxf(REQUIRED_OBSERVATION_SECONDS, 0.001),
		0.0,
		1.0
	)
	var bands_seen := 0
	if seen_shallow:
		bands_seen += 1
	if seen_mid:
		bands_seen += 1
	if seen_deep:
		bands_seen += 1
	var band_ratio := float(bands_seen) / 3.0
	return minf(time_ratio, band_ratio)
