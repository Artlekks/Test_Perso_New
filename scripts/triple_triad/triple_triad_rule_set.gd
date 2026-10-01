extends Resource

@export var open_rule: bool = false
@export var same_rule: bool = false
@export var same_wall_rule: bool = false
@export var plus_rule: bool = false
@export var combo_rule: bool = false
@export var influence_rule: bool = false
@export var elemental_rule: bool = false


func is_basic_only() -> bool:
	return not same_rule and not same_wall_rule and not plus_rule and not combo_rule and not influence_rule and not elemental_rule


func validate_runtime_support() -> Dictionary:
	var errors := PackedStringArray()
	# These switches are reserved for future rules but have no gameplay resolver
	# yet. Reject them explicitly instead of silently pretending they work.
	if same_wall_rule:
		errors.append("Same Wall is enabled but not implemented by the runtime.")
	if elemental_rule:
		errors.append("Elemental is enabled but not implemented by the runtime.")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
	}
