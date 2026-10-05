extends Resource
class_name DialogueLineDefinition

## One authored line of dialogue.
##
## The line owns presentation data only. It never grants items, mutates
## progression, or performs gameplay actions. Runtime context tokens use the
## form {token_name} and are resolved by the dialogue layer at start time.

@export var speaker_id: StringName = &""
@export var speaker_name: String = ""
@export var portrait: Texture2D = null
@export_multiline var text: String = ""


func to_runtime_line(context: Dictionary = {}) -> Dictionary:
	return {
		"speaker_id": speaker_id,
		"speaker_name": speaker_name,
		"portrait": portrait,
		"text": resolve_tokens(text, context),
	}


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if text.strip_edges().is_empty():
		errors.append("Dialogue line text cannot be empty.")
	return errors


static func resolve_tokens(source_text: String, context: Dictionary) -> String:
	var resolved := source_text
	for raw_key in context.keys():
		var token := "{%s}" % str(raw_key)
		resolved = resolved.replace(token, str(context[raw_key]))
	return resolved
