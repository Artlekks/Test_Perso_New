extends RefCounted

## Size-only scoring layer.
##
## This intentionally knows nothing about input, UI, rods, techniques,
## inventory, or persistent progression. Those can add bonuses later without
## changing FishInstance's identity.


static func calculate_points(
	data: FishData,
	size: float,
	is_king: bool
) -> int:
	if data == null:
		return 0

	var max_points := maxi(data.max_points, 0)

	if max_points <= 0:
		return 0

	if is_king:
		return max_points

	var king_threshold := maxf(data.king_size, 0.001)
	var size_ratio := clampf(
		size / king_threshold,
		0.1,
		1.0
	)

	var points := int(round(max_points * size_ratio))

	# Reserve the exact species maximum for a king catch.
	if max_points > 1:
		points = mini(points, max_points - 1)

	return maxi(points, 1)
