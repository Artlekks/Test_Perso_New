extends RefCounted

const ModifierDefinitionScript = preload(
	"res://scripts/database/fishing_session_modifier_definition.gd"
)


static func audit(content_catalog, effect_catalog) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()

	if content_catalog == null:
		errors.append("content catalog is missing")
		return _report(errors, warnings, 0, 0)
	if effect_catalog == null or not effect_catalog.is_valid_catalog():
		errors.append("fish effect catalog is missing or invalid")
		return _report(errors, warnings, 0, 0)

	var fish_ids: Dictionary = {}
	for fish in content_catalog.fish:
		if fish == null:
			continue
		var species_id: String = str(fish.get_stable_species_id()).strip_edges().to_lower()
		fish_ids[species_id] = true
		var effect := effect_catalog.get_effect_for_species(species_id) as ModifierDefinitionScript
		if effect == null:
			errors.append("%s has no fishing consumable effect" % fish.fish_name)
			continue
		if not effect.is_valid_definition():
			errors.append("%s uses invalid effect %s" % [fish.fish_name, str(effect.effect_id)])
		if effect.legacy_bof4_effect.strip_edges().is_empty():
			warnings.append("%s effect has no BOF4 reference text" % fish.fish_name)

	for species_id in effect_catalog.get_species_ids():
		var key := str(species_id).strip_edges().to_lower()
		if not fish_ids.has(key):
			errors.append("effect catalog references unknown fish %s" % key)

	var effect_ids: Dictionary = {}
	for raw_effect in effect_catalog.get_unique_effects():
		var effect := raw_effect as ModifierDefinitionScript
		if effect == null:
			continue
		var key := str(effect.effect_id)
		if effect_ids.has(key):
			errors.append("duplicate effect id %s" % key)
		effect_ids[key] = true

	return _report(
		errors,
		warnings,
		fish_ids.size(),
		effect_ids.size()
	)


static func _report(
	errors: PackedStringArray,
	warnings: PackedStringArray,
	fish_count: int,
	effect_count: int
) -> Dictionary:
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"fish_count": fish_count,
		"effect_count": effect_count,
	}
