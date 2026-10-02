extends RefCounted
class_name TripleTriadBackendValidator

const ProgressionScript = preload("res://scripts/triple_triad/triple_triad_progression.gd")


func validate(config: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var card_catalog = config.get("card_catalog")
	var region_profile = config.get("region_profile")
	var rule_set = config.get("rule_set")
	var opponent_registry = config.get("opponent_registry")
	var acquisition_policy = config.get("acquisition_policy")
	var acquisition_registry = config.get("acquisition_registry")
	var competition_catalog = config.get("competition_catalog")
	var world_acquisition_catalog = config.get("world_acquisition_catalog")
	var player_deck_budget: int = int(config.get("player_deck_budget", 30))

	if card_catalog == null:
		errors.append("Card catalog is missing.")
	elif card_catalog.has_method("validate_catalog"):
		var catalog_audit: Dictionary = card_catalog.call("validate_catalog")
		if not bool(catalog_audit.get("valid", false)):
			errors.append(
				"Invalid card catalog: %s" % str(catalog_audit.get("errors", []))
			)

	if region_profile != null and region_profile.has_method("validate_profile"):
		var default_region_audit: Dictionary = region_profile.call("validate_profile")
		if not bool(default_region_audit.get("valid", false)):
			errors.append(
				"Invalid default region profile: %s"
				% str(default_region_audit.get("errors", []))
			)
	if rule_set != null and rule_set.has_method("validate_runtime_support"):
		var default_rule_audit: Dictionary = rule_set.call("validate_runtime_support")
		if not bool(default_rule_audit.get("valid", false)):
			errors.append(
				"Invalid default rule set: %s"
				% str(default_rule_audit.get("errors", []))
			)

	if opponent_registry == null:
		errors.append("Opponent registry is missing.")
	elif opponent_registry.has_method("validate_registry"):
		var registry_audit: Dictionary = opponent_registry.call(
			"validate_registry",
			card_catalog
		)
		if not bool(registry_audit.get("valid", false)):
			errors.append(
				"Invalid opponent registry: %s"
				% str(registry_audit.get("errors", []))
			)
		for warning in registry_audit.get("warnings", []):
			warnings.append(str(warning))

	if acquisition_policy == null:
		errors.append("Acquisition policy is missing.")
	else:
		for required_method in [
			"can_use_card",
			"build_starting_collection",
			"get_card_lock_reason",
		]:
			if not acquisition_policy.has_method(required_method):
				errors.append(
					"Acquisition policy does not expose %s()." % required_method
				)

		if acquisition_policy.has_method("build_starting_collection") and card_catalog != null:
			var starter_cards: Array = acquisition_policy.call(
				"build_starting_collection",
				card_catalog
			)
			if starter_cards.size() < 5:
				errors.append(
					"Acquisition policy cannot build a five-card starter collection."
				)
			else:
				var starter_costs: Array[int] = []
				for card in starter_cards:
					if card != null:
						starter_costs.append(maxi(0, int(card.deck_cost)))
				starter_costs.sort()
				if starter_costs.size() < 5:
					errors.append("Starter collection contains invalid cards.")
				else:
					var cheapest_starter_deck: int = 0
					for index in range(5):
						cheapest_starter_deck += starter_costs[index]
					if cheapest_starter_deck > player_deck_budget:
						errors.append(
							"Starter collection cannot form a legal deck under the base player budget."
						)

	if acquisition_registry == null:
		errors.append("Acquisition registry is missing.")
	elif acquisition_registry.has_method("validate_registry"):
		var acquisition_audit: Dictionary = acquisition_registry.call(
			"validate_registry",
			card_catalog
		)
		if not bool(acquisition_audit.get("valid", false)):
			errors.append(
				"Invalid acquisition registry: %s"
				% str(acquisition_audit.get("errors", []))
			)
		for warning in acquisition_audit.get("warnings", []):
			warnings.append("acquisition: %s" % str(warning))

	if competition_catalog == null:
		errors.append("Competition catalog is missing.")
	elif competition_catalog.has_method("validate_catalog"):
		var competition_audit: Dictionary = competition_catalog.call("validate_catalog")
		if not bool(competition_audit.get("valid", false)):
			errors.append(
				"Invalid competition catalog: %s"
				% str(competition_audit.get("errors", []))
			)
		for warning in competition_audit.get("warnings", []):
			warnings.append("competition: %s" % str(warning))

	if world_acquisition_catalog == null:
		errors.append("World acquisition catalog is missing.")
	elif world_acquisition_catalog.has_method("validate_map"):
		var world_acquisition_audit: Dictionary = world_acquisition_catalog.call(
			"validate_map"
		)
		if not bool(world_acquisition_audit.get("valid", false)):
			errors.append(
				"Invalid world acquisition map: %s"
				% str(world_acquisition_audit.get("errors", []))
			)
		for warning in world_acquisition_audit.get("warnings", []):
			warnings.append("acquisition map: %s" % str(warning))

	var progression_probe = ProgressionScript.new()
	if (
		progression_probe.progression_catalog == null
		or not progression_probe.progression_catalog.is_valid_catalog()
	):
		errors.append("Progression catalog is invalid.")

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}
