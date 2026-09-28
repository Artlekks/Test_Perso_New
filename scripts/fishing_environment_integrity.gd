extends RefCounted

const ConditionDefinitionScript = preload(
	"res://scripts/database/fishing_environment_condition_definition.gd"
)
const EnvironmentCatalogScript = preload(
	"res://scripts/fishing_environment_catalog.gd"
)


static func audit(
	catalog: EnvironmentCatalogScript,
	content_catalog: FishingContentCatalog
) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var warnings: PackedStringArray = PackedStringArray()

	if catalog == null or not catalog.is_valid_catalog():
		errors.append("environment condition catalog is missing or invalid")
		return _report(errors, warnings, 0)

	var condition_ids: Dictionary = {}
	var condition_groups: Dictionary = {}
	for raw_condition in catalog.conditions:
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition == null:
			continue
		var condition_key: String = str(condition.condition_id).strip_edges().to_lower()
		condition_ids[condition_key] = true
		condition_groups[condition_key] = str(condition.stacking_group).strip_edges().to_lower()

	var default_groups: Dictionary = {}
	for raw_default in catalog.default_condition_ids:
		var default_key: String = str(raw_default).strip_edges().to_lower()
		var default_group: String = str(condition_groups.get(default_key, ""))
		if not default_group.is_empty() and default_groups.has(default_group):
			errors.append("multiple default environment conditions share group %s" % default_group)
		default_groups[default_group] = true

	if content_catalog != null:
		var fish_ids: Dictionary = {}
		for fish in content_catalog.fish:
			if fish != null:
				fish_ids[fish.get_stable_species_id().strip_edges().to_lower()] = true
		for raw_condition in catalog.conditions:
			var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
			if condition == null:
				continue
			for raw_species_id in condition.species_ids:
				var species_id: String = str(raw_species_id).strip_edges().to_lower()
				if not fish_ids.has(species_id):
					errors.append("%s references unknown species %s" % [condition.display_name, species_id])
			for raw_species_id in condition.blocked_species_ids:
				var blocked_species_id: String = str(raw_species_id).strip_edges().to_lower()
				if not fish_ids.has(blocked_species_id):
					errors.append("%s blocks unknown species %s" % [condition.display_name, blocked_species_id])
		for spot in content_catalog.spots:
			if spot == null:
				continue
			for entry in spot.get_fish_population():
				if entry == null:
					continue
				for raw_id in entry.required_environment_conditions:
					var required_id: String = str(raw_id).strip_edges().to_lower()
					if not condition_ids.has(required_id):
						errors.append("%s requires unknown environment condition %s" % [spot.spot_name, required_id])
				for raw_id in entry.blocked_environment_conditions:
					var blocked_id: String = str(raw_id).strip_edges().to_lower()
					if not condition_ids.has(blocked_id):
						errors.append("%s blocks unknown environment condition %s" % [spot.spot_name, blocked_id])
				for raw_required in entry.required_environment_conditions:
					if entry.blocked_environment_conditions.has(raw_required):
						errors.append("%s has the same required and blocked environment condition %s" % [spot.spot_name, str(raw_required)])

	return _report(errors, warnings, condition_ids.size())


static func _report(
	errors: PackedStringArray,
	warnings: PackedStringArray,
	condition_count: int
) -> Dictionary:
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"condition_count": condition_count,
	}
