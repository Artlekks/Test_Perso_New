extends Resource
class_name DialogueLineDefinition

## One authored line of dialogue.
##
## The line owns presentation data only. It never grants items, mutates
## progression, or performs gameplay actions. Runtime context tokens use the
## form {token_name} and are resolved by the dialogue layer at start time.
##
## Choices are also presentation/result data only. Selecting a choice returns a
## stable `choice_id`; the gameplay system that opened the dialogue owns the
## meaning/effect of that id.

@export var speaker_id: StringName = &""
@export var speaker_name: String = ""
@export var portrait: Texture2D = null
@export_multiline var text: String = ""
@export var choices: Array[DialogueChoiceDefinition] = []


func to_runtime_line(context: Dictionary = {}) -> Dictionary:
	var runtime_choices: Array[Dictionary] = []
	for choice in choices:
		if choice == null:
			continue
		runtime_choices.append(choice.to_runtime_choice(context))
	return {
		"speaker_id": speaker_id,
		"speaker_name": speaker_name,
		"portrait": portrait,
		"text": resolve_tokens(text, context),
		"choices": runtime_choices,
	}


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if text.strip_edges().is_empty():
		errors.append("Dialogue line text cannot be empty.")
	var seen_choice_ids: Dictionary = {}
	for index in range(choices.size()):
		var choice := choices[index]
		if choice == null:
			errors.append("Dialogue choice %d is null." % index)
			continue
		var key := String(choice.choice_id)
		if not key.is_empty():
			if seen_choice_ids.has(key):
				errors.append("Duplicate dialogue choice id '%s'." % key)
			else:
				seen_choice_ids[key] = true
		for choice_error in choice.get_validation_errors():
			errors.append("Choice %d: %s" % [index, str(choice_error)])
	return errors


static func resolve_tokens(source_text: String, context: Dictionary) -> String:
	var resolved := source_text
	for raw_key in context.keys():
		var token := "{%s}" % str(raw_key)
		resolved = resolved.replace(token, str(context[raw_key]))
	return resolved
