extends RefCounted

## BOF4-style size scoring layer.
##
## Fishing score is intentionally isolated from input/UI/inventory. A species'
## max_points is awarded once the crown/king threshold is reached. Below that,
## catches score in 10% tiers based on their size relative to king_size.
##
## Example: 68 cm / 70 cm => 90% tier => 270 / 300 points.


static func calculate_points(
	data: FishData,
	size: float,
	is_king: bool
) -> int:
	if data == null:
		return 0

	var max_points: int = maxi(data.max_points, 0)
	if max_points <= 0:
		return 0

	var king_threshold: float = maxf(data.king_size, 0.001)

	# Crown status is size-driven. Keep the bool parameter for compatibility
	# with existing FishInstance/debug code, but a threshold-sized specimen is
	# always worth the species maximum.
	if is_king or size >= king_threshold:
		return max_points

	var size_ratio: float = clampf(
		size / king_threshold,
		0.0,
		0.999999
	)

	# BOF4 record scores step through 10% bands rather than changing every cm.
	# Floor is intentional: 97% of crown size still belongs to the 90% tier.
	var score_tier: int = clampi(
		int(floor(size_ratio * 10.0)),
		1,
		9
	)

	return maxi(
		int(floor(float(max_points * score_tier) / 10.0)),
		1
	)
