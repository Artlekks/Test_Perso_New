extends Resource
class_name DialogueDefinition

## Authored linear dialogue sequence.
##
## v1 deliberately keeps flow linear. The runtime API is isolated from the
## data shape so choices/branches can be layered on later without teaching NPC
## scripts how to render or advance dialogue themselves.

@export var dialogue_id: StringName = &""
@export var allow_cancel: bool = true
@export var lines: Array[DialogueLineDefinition] = []


func to_runtime_lines(context: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for line in lines:
		if line == null:
			continue
		result.append(line.to_runtime_line(context))
	return result


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(dialogue_id).strip_edges().is_empty():
		errors.append("Dialogue definition has an empty dialogue_id.")
	if lines.is_empty():
		errors.append("Dialogue '%s' has no lines." % String(dialogue_id))
	for index in range(lines.size()):
		var line := lines[index]
		if line == null:
			errors.append(
				"Dialogue '%s' line %d is null."
				% [String(dialogue_id), index]
			)
			continue
		for line_error in line.get_validation_errors():
			errors.append(
				"Dialogue '%s' line %d: %s"
				% [String(dialogue_id), index, str(line_error)]
			)
	return errors
