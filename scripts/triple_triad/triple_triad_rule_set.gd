extends Resource

@export var open_rule: bool = false
@export var same_rule: bool = false
@export var same_wall_rule: bool = false
@export var plus_rule: bool = false
@export var combo_rule: bool = false
@export var elemental_rule: bool = false


func is_basic_only() -> bool:
	return not same_rule and not same_wall_rule and not plus_rule and not combo_rule and not elemental_rule
