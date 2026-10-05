extends Resource
class_name WorldRequestCatalog

## Data-only catalog of authored world-request definitions.
##
## The catalog is intentionally presentation/progression neutral. Runtime
## request sources still own their objective adapters and state transitions.

@export var definitions: Array[Resource] = []


func get_definition(request_id: StringName) -> Resource:
	for definition in definitions:
		if definition == null:
			continue
		if StringName(str(definition.get("request_id"))) == request_id:
			return definition
	return null


func has_definition(request_id: StringName) -> bool:
	return get_definition(request_id) != null


func get_definition_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for definition in definitions:
		if definition == null:
			continue
		ids.append(StringName(str(definition.get("request_id"))))
	return ids


func audit() -> Dictionary:
	var errors := PackedStringArray()
	var seen: Dictionary = {}
	for index in range(definitions.size()):
		var definition = definitions[index]
		if definition == null:
			errors.append("definition %d is null" % index)
			continue
		var request_id := StringName(str(definition.get("request_id")))
		if request_id == &"":
			errors.append("definition %d has an empty request_id" % index)
		else:
			var key := String(request_id)
			if seen.has(key):
				errors.append("duplicate request_id: %s" % key)
			seen[key] = true
		if definition.has_method("audit"):
			var definition_errors = definition.call("audit")
			if definition_errors is PackedStringArray:
				for error_text in definition_errors:
					errors.append(str(error_text))
	return {
		"definition_count": definitions.size(),
		"errors": errors,
	}
