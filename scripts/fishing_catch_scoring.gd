extends RefCounted

## Authoritative specimen classification + score math.
##
## This file owns the definition of:
## - king/crown threshold
## - normal / near-record / king size band
## - coarse 10% score tier metadata
## - continuous per-centimetre points awarded for one specimen
##
## Runtime fish, persistence migration, debug catches and journal screens all
## consume this same policy instead of reimplementing size/king logic.

const SCORE_TIER_COUNT: int = 10
const KING_SCORE_TIER: int = 10


static func normalize_size_cm(size: float) -> float:
	return float(maxi(roundi(size), 0))


static func get_king_threshold_cm(data: FishData) -> float:
	if data == null:
		return 0.0

	return maxf(data.king_size, 0.0)


static func get_size_ratio_to_king(
	data: FishData,
	size: float
) -> float:
	if data == null:
		return 0.0

	var king_threshold: float = maxf(
		get_king_threshold_cm(data),
		0.001
	)

	return maxf(
		normalize_size_cm(size) / king_threshold,
		0.0
	)


static func is_king_size(
	data: FishData,
	size: float
) -> bool:
	if data == null:
		return false

	var king_threshold: float = get_king_threshold_cm(data)
	if king_threshold <= 0.0:
		return false

	return normalize_size_cm(size) >= king_threshold


static func get_near_record_min_cm(
	data: FishData
) -> int:
	if data == null:
		return 0

	var king_cm: int = maxi(
		ceili(maxf(data.king_size, 1.0)),
		1
	)

	if king_cm <= 1:
		return 1

	var ratio: float = clampf(
		data.near_record_min_size_ratio,
		0.75,
		0.99
	)

	return clampi(
		ceili(float(king_cm) * ratio),
		1,
		king_cm - 1
	)


static func get_size_band(
	data: FishData,
	size: float
) -> StringName:
	if data == null:
		return &"normal"

	var normalized_size: float = normalize_size_cm(size)

	if is_king_size(data, normalized_size):
		return &"king"

	var near_record_min: int = get_near_record_min_cm(data)

	if (
		near_record_min > 0
		and normalized_size >= float(near_record_min)
	):
		return &"near_record"

	return &"normal"


## Coarse metadata retained for journal/debug compatibility. Actual points are
## intentionally more granular and are calculated per centimetre below.
static func get_score_tier(
	data: FishData,
	size: float
) -> int:
	if data == null:
		return 0

	var max_points: int = maxi(data.max_points, 0)
	var normalized_size: float = normalize_size_cm(size)

	if max_points <= 0 or normalized_size <= 0.0:
		return 0

	if is_king_size(data, normalized_size):
		return KING_SCORE_TIER

	var king_threshold: float = maxf(
		get_king_threshold_cm(data),
		0.001
	)
	var size_ratio: float = clampf(
		normalized_size / king_threshold,
		0.0,
		0.999999
	)

	return clampi(
		int(floor(size_ratio * float(SCORE_TIER_COUNT))),
		1,
		SCORE_TIER_COUNT - 1
	)


static func calculate_points(
	data: FishData,
	size: float,
	_is_king_hint: bool = false
) -> int:
	if data == null:
		return 0

	var max_points: int = maxi(data.max_points, 0)
	var normalized_size: float = normalize_size_cm(size)
	if max_points <= 0 or normalized_size <= 0.0:
		return 0

	if is_king_size(data, normalized_size):
		return max_points

	var king_threshold: float = maxf(
		get_king_threshold_cm(data),
		0.001
	)
	var size_ratio: float = clampf(
		normalized_size / king_threshold,
		0.0,
		0.999999
	)

	# Each centimetre now contributes directly toward the species' maximum
	# score. This keeps the familiar larger-fish = more-points rule while
	# avoiding broad 10% plateaus where several visibly different specimens
	# produced identical points.
	return clampi(
		roundi(float(max_points) * size_ratio),
		1,
		maxi(max_points - 1, 1)
	)


static func evaluate(
	data: FishData,
	size: float
) -> Dictionary:
	if data == null:
		return {}

	var normalized_size: float = normalize_size_cm(size)
	var max_points: int = maxi(data.max_points, 0)
	var points: int = calculate_points(
		data,
		normalized_size
	)
	var score_tier: int = get_score_tier(
		data,
		normalized_size
	)
	var ratio_to_king: float = get_size_ratio_to_king(
		data,
		normalized_size
	)

	return {
		"size": normalized_size,
		"is_king": is_king_size(
			data,
			normalized_size
		),
		"size_band": get_size_band(
			data,
			normalized_size
		),
		"score_tier": score_tier,
		"score_tier_count": SCORE_TIER_COUNT,
		"points": points,
		"max_points": max_points,
		"points_remaining": maxi(
			max_points - points,
			0
		),
		"average_size": maxf(data.average_size, 0.0),
		"king_size": get_king_threshold_cm(data),
		"size_ratio_to_king": ratio_to_king,
		"score_completion_ratio": (
			clampf(
				float(points) / float(max_points),
				0.0,
				1.0
			)
			if max_points > 0
			else 0.0
		),
	}
