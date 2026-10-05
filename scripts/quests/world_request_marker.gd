extends Node3D
class_name WorldRequestMarker

## Presentation-only marker for small world requests.
##
## The request owner supplies a stable state id. This node decides only how that
## state should be advertised in the world. It owns no acceptance, objective,
## reward, inventory, or save logic.

@export var available_text: String = "!"
@export var accepted_text: String = "*"
@export var ready_text: String = "?"

@export var available_color: Color = Color(1.0, 0.86, 0.32, 1.0)
@export var accepted_color: Color = Color(0.62, 0.84, 1.0, 1.0)
@export var ready_color: Color = Color(1.0, 0.94, 0.48, 1.0)

@onready var label: Label3D = $Label3D

var _state_id: StringName = &"locked"
var _requested_visible: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_request_state(_state_id)


func _process(_delta: float) -> void:
	_apply_visibility()


func set_request_state(state_id: StringName) -> void:
	_state_id = state_id
	var presentation: Dictionary = presentation_for_state(state_id)
	_requested_visible = bool(presentation.get("visible", false))

	if label != null:
		match state_id:
			&"available":
				label.text = available_text
				label.modulate = available_color
			&"accepted":
				label.text = accepted_text
				label.modulate = accepted_color
			&"ready_to_turn_in":
				label.text = ready_text
				label.modulate = ready_color
			_:
				label.text = ""

	_apply_visibility()


func get_request_state() -> StringName:
	return _state_id


func _apply_visibility() -> void:
	var parent_enabled := true
	var owner_node := get_parent()
	if owner_node != null:
		parent_enabled = owner_node.is_processing_input()
	if label != null:
		label.visible = _requested_visible and parent_enabled


static func presentation_for_state(state_id: StringName) -> Dictionary:
	match state_id:
		&"available":
			return {"visible": true, "marker": "!"}
		&"accepted":
			return {"visible": true, "marker": "*"}
		&"ready_to_turn_in":
			return {"visible": true, "marker": "?"}
	return {"visible": false, "marker": ""}
