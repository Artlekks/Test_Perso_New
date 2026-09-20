extends Node
class_name FishSelector


func choose(
	entries: Array[FishSpawnEntry],
	bait: BaitData,
	current_depth: float,
	total_depth: float
) -> FishSpawnEntry:
	var total_weight := 0.0

	for entry in entries:
		if entry == null or entry.fish == null or entry.weight <= 0.0:
			continue

		var lure_multiplier := entry.fish.get_lure_match_multiplier(bait)
		var depth_multiplier := entry.fish.get_depth_match_multiplier(
			current_depth,
			total_depth
		)

		total_weight += (
			entry.weight
			* lure_multiplier
			* depth_multiplier
		)

	if total_weight <= 0.0:
		return null

	var roll := randf() * total_weight

	for entry in entries:
		if entry == null or entry.fish == null or entry.weight <= 0.0:
			continue

		var lure_multiplier := entry.fish.get_lure_match_multiplier(bait)
		var depth_multiplier := entry.fish.get_depth_match_multiplier(
			current_depth,
			total_depth
		)

		roll -= (
			entry.weight
			* lure_multiplier
			* depth_multiplier
		)

		if roll <= 0.0:
			return entry

	return null


func get_attraction_ratio(
	entries: Array[FishSpawnEntry],
	bait: BaitData,
	current_depth: float,
	total_depth: float
) -> float:
	var base_weight_total := 0.0
	var effective_weight_total := 0.0

	for entry in entries:
		if entry == null or entry.fish == null or entry.weight <= 0.0:
			continue

		base_weight_total += entry.weight

		var lure_multiplier := entry.fish.get_lure_match_multiplier(bait)
		var depth_multiplier := entry.fish.get_depth_match_multiplier(
			current_depth,
			total_depth
		)

		effective_weight_total += (
			entry.weight
			* lure_multiplier
			* depth_multiplier
		)

	if base_weight_total <= 0.0:
		return 0.0

	return clampf(
		effective_weight_total / base_weight_total,
		0.0,
		1.0
	)
