extends Resource

const ModifierDefinitionScript = preload(
	"res://scripts/database/fishing_session_modifier_definition.gd"
)

## Maps stable fish species IDs to fishing-session effects.
## Parallel arrays keep the resource compact and Inspector-editable without
## embedding gameplay logic in FishData or UI code.

@export var species_ids: PackedStringArray = []
@export var effects: Array[Resource] = []


func get_effect_for_species(species_id: String) -> ModifierDefinitionScript:
	var key := species_id.strip_edges().to_lower()
	if key.is_empty():
		return null

	var limit := mini(species_ids.size(), effects.size())
	for index in range(limit):
		if str(species_ids[index]).strip_edges().to_lower() != key:
			continue
		return effects[index] as ModifierDefinitionScript

	return null


func get_effect_by_id(effect_id: StringName) -> ModifierDefinitionScript:
	if effect_id == &"":
		return null

	for raw_effect in effects:
		var effect := raw_effect as ModifierDefinitionScript
		if effect != null and effect.effect_id == effect_id:
			return effect

	return null


func get_species_ids() -> PackedStringArray:
	return species_ids.duplicate()


func get_unique_effects() -> Array[Resource]:
	var result: Array[Resource] = []
	var seen: Dictionary = {}
	for raw_effect in effects:
		var effect := raw_effect as ModifierDefinitionScript
		if effect == null:
			continue
		var key := str(effect.effect_id)
		if seen.has(key):
			continue
		seen[key] = true
		result.append(effect)
	return result


func is_valid_catalog() -> bool:
	if species_ids.is_empty() or species_ids.size() != effects.size():
		return false

	var seen_species: Dictionary = {}
	for index in range(species_ids.size()):
		var species_id := str(species_ids[index]).strip_edges().to_lower()
		var effect := effects[index] as ModifierDefinitionScript
		if species_id.is_empty() or seen_species.has(species_id):
			return false
		if effect == null or not effect.is_valid_definition():
			return false
		seen_species[species_id] = true

	return true
