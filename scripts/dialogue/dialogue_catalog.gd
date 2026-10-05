extends Resource
class_name DialogueCatalog

## Central authored dialogue registry.
##
## NPCs ask for dialogue by stable id; they do not preload individual .tres
## files. This keeps world scenes independent from dialogue asset layout.

@export var dialogues: Array[DialogueDefinition] = []


func has_dialogue(dialogue_id: StringName) -> bool:
	return get_dialogue(dialogue_id) != null


func get_dialogue(dialogue_id: StringName) -> DialogueDefinition:
	if dialogue_id == &"":
		return null
	for definition in dialogues:
		if definition != null and definition.dialogue_id == dialogue_id:
			return definition
	return null


func get_dialogue_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for definition in dialogues:
		if definition == null or definition.dialogue_id == &"":
			continue
		result.append(definition.dialogue_id)
	return result


func audit() -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var seen: Dictionary = {}

	for index in range(dialogues.size()):
		var definition := dialogues[index]
		if definition == null:
			errors.append("Dialogue catalog entry %d is null." % index)
			continue
		var key := String(definition.dialogue_id)
		if key.is_empty():
			errors.append("Dialogue catalog entry %d has an empty id." % index)
		elif seen.has(key):
			errors.append("Duplicate dialogue id '%s'." % key)
		else:
			seen[key] = true
		for definition_error in definition.get_validation_errors():
			errors.append(str(definition_error))

	if dialogues.is_empty():
		warnings.append("Dialogue catalog is empty.")

	return {
		"errors": errors,
		"warnings": warnings,
		"dialogue_count": seen.size(),
	}
