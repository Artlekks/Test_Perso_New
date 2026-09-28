extends Resource
class_name FishingProgressionCatalog

@export_category("Global")
@export_range(1, 999999, 1)
var max_fishing_points: int = 9999

@export_category("Ranks")
## Keep authored in ascending min_points order.
@export var ranks: Array[FishingRankDefinition] = []


func is_valid_catalog() -> bool:
	if max_fishing_points <= 0 or ranks.is_empty():
		return false

	var previous_min: int = -1
	var seen_ids: Dictionary = {}
	var seen_names: Dictionary = {}

	for index in range(ranks.size()):
		var rank: FishingRankDefinition = ranks[index]
		if rank == null or not rank.is_valid_definition():
			return false

		# Rank zero is the baseline state and must exist before the player has
		# caught anything. Every later threshold must be strictly increasing.
		if index == 0 and rank.min_points != 0:
			return false
		if index > 0 and rank.min_points <= previous_min:
			return false
		if rank.min_points > max_fishing_points:
			return false

		var id_key: String = str(rank.rank_id).strip_edges().to_lower()
		var name_key: String = rank.display_name.strip_edges().to_lower()
		if seen_ids.has(id_key) or seen_names.has(name_key):
			return false
		seen_ids[id_key] = true
		seen_names[name_key] = true
		previous_min = rank.min_points

	return true


func clamp_points(points: int) -> int:
	return clampi(
		points,
		0,
		maxi(max_fishing_points, 1)
	)


func get_rank_count() -> int:
	return ranks.size()


func get_rank_index(points: int) -> int:
	if ranks.is_empty():
		return 0

	var value: int = clamp_points(points)
	var index: int = 0

	for candidate_index in range(ranks.size()):
		var rank: FishingRankDefinition = ranks[candidate_index]

		if rank == null:
			continue

		if value < rank.min_points:
			break

		index = candidate_index

	return index


func get_rank(points: int) -> FishingRankDefinition:
	if ranks.is_empty():
		return null

	return ranks[
		clampi(
			get_rank_index(points),
			0,
			ranks.size() - 1
		)
	]


func get_rank_name(points: int) -> String:
	var rank: FishingRankDefinition = get_rank(points)

	if rank == null:
		return ""

	return rank.display_name


func get_rank_id(points: int) -> StringName:
	var rank: FishingRankDefinition = get_rank(points)

	if rank == null:
		return &""

	return rank.rank_id


func get_next_rank_threshold(points: int) -> int:
	if ranks.is_empty():
		return maxi(max_fishing_points, 1)

	var value: int = clamp_points(points)
	var current_index: int = get_rank_index(value)

	if current_index >= ranks.size() - 1:
		return maxi(max_fishing_points, 1)

	var next_rank: FishingRankDefinition = ranks[
		current_index + 1
	]

	if next_rank == null:
		return maxi(max_fishing_points, 1)

	return clampi(
		next_rank.min_points,
		0,
		maxi(max_fishing_points, 1)
	)


func get_rank_progress(points: int) -> Dictionary:
	if ranks.is_empty():
		return {
			"index": 0,
			"id": "",
			"name": "",
			"points": 0,
			"current_min": 0,
			"next_threshold": maxi(max_fishing_points, 1),
			"is_max_rank": true,
			"points_into_rank": 0,
			"rank_span_points": maxi(max_fishing_points, 1),
			"points_to_next": maxi(max_fishing_points, 1),
			"progress_ratio": 0.0,
			"max_fishing_points": maxi(max_fishing_points, 1),
		}

	var value: int = clamp_points(points)
	var index: int = get_rank_index(value)
	var current_rank: FishingRankDefinition = ranks[index]
	var current_min: int = current_rank.min_points
	var next_threshold: int = get_next_rank_threshold(value)
	var is_max_rank: bool = index >= ranks.size() - 1

	# Preserve useful progress from the final rank threshold to a perfect 9999.
	var span_end: int = (
		max_fishing_points
		if is_max_rank
		else next_threshold
	)
	var span_size: int = maxi(
		span_end - current_min,
		1
	)
	var points_into_rank: int = clampi(
		value - current_min,
		0,
		span_size
	)

	return {
		"index": index,
		"id": str(current_rank.rank_id),
		"name": current_rank.display_name,
		"points": value,
		"current_min": current_min,
		"next_threshold": next_threshold,
		"is_max_rank": is_max_rank,
		"points_into_rank": points_into_rank,
		"rank_span_points": span_size,
		"points_to_next": maxi(
			span_end - value,
			0
		),
		"progress_ratio": clampf(
			float(points_into_rank) / float(span_size),
			0.0,
			1.0
		),
		"max_fishing_points": max_fishing_points,
	}


func get_crossed_ranks(from_points: int, to_points: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if ranks.is_empty():
		return result

	var from_value: int = clamp_points(from_points)
	var to_value: int = clamp_points(to_points)
	if to_value <= from_value:
		return result

	var from_index: int = get_rank_index(from_value)
	var to_index: int = get_rank_index(to_value)
	if to_index <= from_index:
		return result

	for index in range(from_index + 1, to_index + 1):
		var rank: FishingRankDefinition = ranks[index]
		if rank == null:
			continue
		result.append({
			"index": index,
			"id": str(rank.rank_id),
			"name": rank.display_name,
			"threshold": rank.min_points,
		})

	return result


func get_debug_summary(points: int) -> String:
	var progress: Dictionary = get_rank_progress(points)

	return "%s | %d/%d | next %d | %.0f%%" % [
		str(progress.get("name", "")),
		int(progress.get("points", 0)),
		int(progress.get("max_fishing_points", 0)),
		int(progress.get("next_threshold", 0)),
		float(progress.get("progress_ratio", 0.0)) * 100.0,
	]
