extends RefCounted

## Cross-catalog integrity audit for the complete fishing progression loop.
## This is intentionally pure/read-only: it validates authored data and returns
## a report, but never repairs or mutates runtime state behind the designer's back.

static func audit(
	progression_catalog: FishingProgressionCatalog,
	reward_catalog: FishingRewardCatalog,
	content_catalog: FishingContentCatalog
) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var details: Dictionary = {
		"rank_count": 0,
		"reward_count": 0,
		"species_count": 0,
		"species_max_points_total": 0,
		"progression_max_points": 0,
	}

	if progression_catalog == null:
		errors.append("Progression catalog is missing.")
	else:
		details["rank_count"] = progression_catalog.get_rank_count()
		details["progression_max_points"] = progression_catalog.max_fishing_points
		if not progression_catalog.is_valid_catalog():
			errors.append("Progression catalog failed its internal validation.")

	if reward_catalog == null:
		errors.append("Reward catalog is missing.")
	else:
		details["reward_count"] = reward_catalog.get_all_rewards().size()
		if not reward_catalog.is_valid_catalog():
			errors.append("Reward catalog failed its internal validation.")

	if content_catalog == null:
		errors.append("Fishing content catalog is missing.")
	else:
		_audit_species(content_catalog, progression_catalog, errors, warnings, details)

	if progression_catalog != null and reward_catalog != null:
		_audit_rewards(
			reward_catalog,
			progression_catalog,
			content_catalog,
			errors,
			warnings
		)

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"details": details,
	}


static func _audit_species(
	content_catalog: FishingContentCatalog,
	progression_catalog: FishingProgressionCatalog,
	errors: PackedStringArray,
	warnings: PackedStringArray,
	details: Dictionary
) -> void:
	var seen_species: Dictionary = {}
	var max_points_total: int = 0
	var valid_species_count: int = 0

	for fish in content_catalog.fish:
		if fish == null:
			errors.append("Fishing content contains a null fish resource.")
			continue

		var species_id: String = fish.get_stable_species_id().strip_edges().to_lower()
		if species_id.is_empty():
			errors.append("A fish has no stable species id: %s" % fish.fish_name)
			continue

		if seen_species.has(species_id):
			errors.append("Duplicate stable species id: %s" % species_id)
			continue

		seen_species[species_id] = true
		valid_species_count += 1

		if fish.max_points <= 0:
			errors.append("%s has non-positive max_points." % species_id)
		else:
			max_points_total += fish.max_points

		if fish.king_size <= 0.0:
			errors.append("%s has a non-positive king size." % species_id)

	details["species_count"] = valid_species_count
	details["species_max_points_total"] = max_points_total

	if progression_catalog != null:
		if max_points_total != progression_catalog.max_fishing_points:
			errors.append(
				"Perfect-score mismatch: species max points total %d, progression max %d."
				% [max_points_total, progression_catalog.max_fishing_points]
			)

		if progression_catalog.get_rank_count() > 0:
			var final_rank: FishingRankDefinition = progression_catalog.ranks[
				progression_catalog.ranks.size() - 1
			]
			if final_rank != null and final_rank.min_points > max_points_total:
				errors.append("Final rank is unreachable from authored fish scores.")

	if valid_species_count <= 0:
		warnings.append("No valid fish species were found for progression auditing.")


static func _audit_rewards(
	reward_catalog: FishingRewardCatalog,
	progression_catalog: FishingProgressionCatalog,
	content_catalog: FishingContentCatalog,
	errors: PackedStringArray,
	warnings: PackedStringArray
) -> void:
	var valid_species: Dictionary = {}
	if content_catalog != null:
		for fish in content_catalog.fish:
			if fish != null:
				valid_species[fish.get_stable_species_id().strip_edges().to_lower()] = true

	for reward in reward_catalog.get_all_rewards():
		if reward == null:
			continue

		var key: String = str(reward.reward_key)
		match reward.trigger_type:
			FishingRewardDefinition.TriggerType.FISHING_POINTS:
				if reward.threshold < 0 or reward.threshold > progression_catalog.max_fishing_points:
					errors.append(
						"Reward %s has unreachable fishing-points threshold %d."
						% [key, reward.threshold]
					)

			FishingRewardDefinition.TriggerType.RANK_INDEX:
				if reward.threshold < 0 or reward.threshold >= progression_catalog.get_rank_count():
					errors.append(
						"Reward %s references invalid rank index %d."
						% [key, reward.threshold]
					)

			FishingRewardDefinition.TriggerType.TOTAL_CATCHES:
				if reward.threshold <= 0:
					errors.append("Reward %s needs a positive catch threshold." % key)

			FishingRewardDefinition.TriggerType.SPECIES_CATCH_COUNT, FishingRewardDefinition.TriggerType.KING_CAUGHT:
				var species_id: String = reward.species_id.strip_edges().to_lower()
				if not valid_species.has(species_id):
					errors.append(
						"Reward %s references unknown species %s."
						% [key, species_id]
					)

		if content_catalog != null and content_catalog.tackle != null:
			match reward.reward_type:
				FishingRewardDefinition.RewardType.LURE:
					if not content_catalog.tackle.has_lure(reward.reward_item_id):
						errors.append(
							"Reward %s references unknown lure %s."
							% [key, str(reward.reward_item_id)]
						)
				FishingRewardDefinition.RewardType.ROD:
					if not content_catalog.tackle.has_rod(reward.reward_item_id):
						errors.append(
							"Reward %s references unknown rod %s."
							% [key, str(reward.reward_item_id)]
						)

		if reward.claim_source_id == &"" and not reward.auto_claim:
			warnings.append(
				"Reward %s is manual but has no claim source id." % key
			)
