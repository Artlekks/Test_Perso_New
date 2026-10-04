extends Resource
class_name FishingMasteryTechniqueCatalog

@export var techniques: Array[FishingMasteryTechniqueDefinition] = []


func get_technique(technique_id: StringName) -> FishingMasteryTechniqueDefinition:
	var key := str(technique_id).strip_edges().to_lower()
	if key.is_empty():
		return null
	for technique in techniques:
		if technique == null:
			continue
		if str(technique.technique_id).strip_edges().to_lower() == key:
			return technique
	return null


func get_technique_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for technique in techniques:
		if technique != null:
			result.append(str(technique.technique_id))
	return result


func get_by_capability(capability: StringName) -> Array[FishingMasteryTechniqueDefinition]:
	var result: Array[FishingMasteryTechniqueDefinition] = []
	for technique in techniques:
		if technique != null and technique.has_capability(capability):
			result.append(technique)
	return result


func is_valid_catalog() -> bool:
	if techniques.is_empty():
		return false
	var seen: Dictionary = {}
	for technique in techniques:
		if technique == null or not technique.is_valid_definition():
			return false
		var key := str(technique.technique_id).strip_edges().to_lower()
		if seen.has(key):
			return false
		seen[key] = true
	for technique in techniques:
		for raw_prereq in technique.prerequisite_ids:
			var prereq := str(raw_prereq).strip_edges().to_lower()
			if prereq.is_empty() or prereq == str(technique.technique_id).to_lower():
				return false
			if not seen.has(prereq):
				return false
	return true
