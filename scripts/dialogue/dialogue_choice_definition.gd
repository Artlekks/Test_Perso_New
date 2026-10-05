extends Resource
class_name DialogueChoiceDefinition

## One presentation-only choice exposed by a dialogue line.
##
## `choice_id` is the stable result returned to the caller. The dialogue layer
## never interprets that id as a shop/reward/quest action; the NPC or gameplay
## system that opened the conversation decides what the selected id means.

@export var choice_id: StringName = &""
@export var text: String = ""
@export var enabled: bool = true
@export var metadata: Dictionary = {}


func to_runtime_choice(context: Dictionary = {}) -> Dictionary:
	return {
		"choice_id": choice_id,
		"text": _resolve_tokens(text, context),
		"enabled": enabled,
		"metadata": metadata.duplicate(true),
	}


static func _resolve_tokens(source_text: String, context: Dictionary) -> String:
	var resolved := source_text
	for raw_key in context.keys():
		var token := "{%s}" % str(raw_key)
		resolved = resolved.replace(token, str(context[raw_key]))
	return resolved


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(choice_id).strip_edges().is_empty():
		errors.append("Dialogue choice has an empty choice_id.")
	if text.strip_edges().is_empty():
		errors.append("Dialogue choice '%s' has empty text." % String(choice_id))
	return errors
