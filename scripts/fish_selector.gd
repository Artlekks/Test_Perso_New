extends Node
class_name FishSelector


func choose(
	entries: Array[FishSpawnEntry],
	bait: BaitData,
	current_depth: float,
	total_depth: float,
	is_reeling: bool = false,
	spatial_context: Dictionary = {}
) -> FishSpawnEntry:
	var total_weight: float = 0.0

	for entry in entries:
		if entry == null:
			continue

		total_weight += (
			entry.get_bite_selection_weight(
				bait,
				current_depth,
				total_depth,
				is_reeling
			)
			* _get_spatial_species_multiplier(
				entry,
				spatial_context
			)
		)

	if total_weight <= 0.0:
		return null

	var roll: float = randf() * total_weight

	for entry in entries:
		if entry == null:
			continue

		roll -= (
			entry.get_bite_selection_weight(
				bait,
				current_depth,
				total_depth,
				is_reeling
			)
			* _get_spatial_species_multiplier(
				entry,
				spatial_context
			)
		)

		if roll <= 0.0:
			return entry

	return null


func get_attraction_ratio(
	entries: Array[FishSpawnEntry],
	bait: BaitData,
	current_depth: float,
	total_depth: float,
	is_reeling: bool = false,
	spatial_context: Dictionary = {}
) -> float:
	var base_weight_total: float = 0.0
	var effective_weight_total: float = 0.0

	for entry in entries:
		if entry == null:
			continue

		base_weight_total += entry.get_base_bite_weight()
		effective_weight_total += (
			entry.get_bite_selection_weight(
				bait,
				current_depth,
				total_depth,
				is_reeling
			)
			* _get_spatial_species_multiplier(
				entry,
				spatial_context
			)
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



func _get_spatial_species_multiplier(
	entry: FishSpawnEntry,
	spatial_context: Dictionary
) -> float:
	if (
		entry == null
		or entry.fish == null
		or spatial_context.is_empty()
	):
		return 1.0

	var multipliers: Dictionary = (
		spatial_context.get(
			"species_multipliers",
			{}
		) as Dictionary
	)
	var species_id: String = (
		entry.fish.get_stable_species_id()
		.strip_edges()
		.to_lower()
	)

	return maxf(
		float(
			multipliers.get(
				species_id,
				1.0
			)
		),
		0.0
	)
