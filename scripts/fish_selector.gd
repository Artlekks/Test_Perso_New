extends Node
class_name FishSelector


func choose(
	entries: Array[FishSpawnEntry],
	bait: BaitData,
	current_depth: float,
	total_depth: float,
	is_reeling: bool = false
) -> FishSpawnEntry:
	var total_weight: float = 0.0

	for entry in entries:
		if entry == null:
			continue

		total_weight += entry.get_bite_selection_weight(
			bait,
			current_depth,
			total_depth,
			is_reeling
		)

	if total_weight <= 0.0:
		return null

	var roll: float = randf() * total_weight

	for entry in entries:
		if entry == null:
			continue

		roll -= entry.get_bite_selection_weight(
			bait,
			current_depth,
			total_depth,
			is_reeling
		)

		if roll <= 0.0:
			return entry

	return null


func get_attraction_ratio(
	entries: Array[FishSpawnEntry],
	bait: BaitData,
	current_depth: float,
	total_depth: float,
	is_reeling: bool = false
) -> float:
	var base_weight_total: float = 0.0
	var effective_weight_total: float = 0.0

	for entry in entries:
		if entry == null:
			continue

		base_weight_total += entry.get_base_bite_weight()
		effective_weight_total += entry.get_bite_selection_weight(
			bait,
			current_depth,
			total_depth,
			is_reeling
		)

	if base_weight_total <= 0.0:
		return 0.0

	# Values above 1.0 still matter for species selection in choose(). Encounter
	# consumes this as a safe probability input, so clamp only at this boundary.
	return clampf(
		effective_weight_total / base_weight_total,
		0.0,
		1.0
	)
