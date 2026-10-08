extends CanvasLayer
class_name FishingInfoView
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")

enum Priority {
	NORMAL,
	IMPORTANT,
	CRITICAL
}


@onready var root: Control = $Root
@onready var message_label: Label = $Root/MessageLabel


@export_category("Timing")
@export var default_duration: float = 2.0
@export var slide_time: float = 0.25
@export var slide_padding_px: float = 30.0

@export_category("Context Layout")
## Fishing keeps the scene-authored top position. Exploration moves the same
## compact HUD notice beside the bottom-left exploration Menu panel.
@export var exploration_position: Vector2 = Vector2(170.0, 430.0)
@export var game_mode_node_name: StringName = &"GameMode"

var _message_queue: Array[Dictionary] = []
var _current_priority: int = -1
var _message_tween: Tween = null
var _showing_message: bool = false
var _rest_position: Vector2 = Vector2.ZERO
var _fishing_rest_position: Vector2 = Vector2.ZERO
var _game_mode: Node = null
var _using_fishing_layout: bool = false


func _ready() -> void:
	_fishing_rest_position = root.position
	_rest_position = _fishing_rest_position
	root.visible = false

	_bind_game_mode()
	_apply_layout_from_game_mode(false)

	if _game_mode == null:
		call_deferred("_late_bind_game_mode")


func get_fishing_covered_bottom_ratio() -> float:
	# Measure the resting bar even while hidden/sliding, so showing a notice
	# never changes the available water area underneath an existing lure.
	var bottom := 0.0
	for control in [root.get_node("InfoFrame"), message_label]:
		var transform: Transform2D = control.get_global_transform_with_canvas()
		var rest_shift: Vector2 = root.get_global_transform_with_canvas().basis_xform(_fishing_rest_position - root.position)
		for corner in [Vector2.ZERO, Vector2(control.size.x, 0), control.size, Vector2(0, control.size.y)]:
			bottom = maxf(bottom, (transform * corner + rest_shift).y)
	return bottom / maxf(get_viewport().get_visible_rect().size.y, 1.0)


func show_message(
	text: String,
	duration: float = -1.0,
	priority: Priority = Priority.NORMAL
) -> void:
	var actual_duration := duration

	if actual_duration <= 0.0:
		actual_duration = default_duration

	var message := {
		"text": text,
		"duration": actual_duration,
		"priority": int(priority)
	}

	# Important messages can interrupt less-important ones.
	if _showing_message and int(priority) > _current_priority:
		_interrupt_with_message(message)
		return

	_message_queue.append(message)

	if not _showing_message:
		_show_next_message()


func clear() -> void:
	_kill_message_tween()

	_message_queue.clear()
	_current_priority = -1
	_showing_message = false

	root.visible = false
	root.position = _rest_position


func _show_next_message() -> void:
	if _message_queue.is_empty():
		_current_priority = -1
		_showing_message = false
		root.visible = false
		return

	var message: Dictionary = _message_queue.pop_front()
	_display_message(message)


func _display_message(message: Dictionary) -> void:
	_kill_message_tween()

	_showing_message = true
	_current_priority = message["priority"]
	message_label.text = message["text"]

	root.position = _get_hidden_position()
	root.visible = true

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)

	# Hidden edge -> contextual resting position.
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(
		root,
		"position",
		_rest_position,
		slide_time
	)

	# Stay visible.
	tween.tween_interval(message["duration"])

	# Contextual resting position -> hidden edge.
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(
		root,
		"position",
		_get_hidden_position(),
		slide_time
	)

	tween.tween_callback(_on_message_finished)
	_message_tween = tween


func _interrupt_with_message(message: Dictionary) -> void:
	_kill_message_tween()
	_display_message(message)


func _on_message_finished() -> void:
	_message_tween = null
	_showing_message = false
	_current_priority = -1

	root.visible = false
	root.position = _rest_position
	_show_next_message()


func _kill_message_tween() -> void:
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = null


func _get_hidden_position() -> Vector2:
	if _using_fishing_layout:
		return Vector2(
			_rest_position.x,
			-root.size.y - slide_padding_px
		)

	# Exploration HUD lives along the top and bottom-left. The info strip rests
	# beside the Menu panel and enters/exits through the bottom edge so it never
	# travels through the compass/location banner.
	var viewport_height := get_viewport().get_visible_rect().size.y
	return Vector2(
		_rest_position.x,
		viewport_height + root.size.y + slide_padding_px
	)


func _late_bind_game_mode() -> void:
	_bind_game_mode()
	_apply_layout_from_game_mode(false)


func _bind_game_mode() -> void:
	if is_instance_valid(_game_mode):
		return

	var tree := get_tree()
	if tree == null or GameplaySceneRoot.resolve(tree) == null:
		return

	_game_mode = GameplaySceneRoot.resolve(tree).find_child(
		String(game_mode_node_name),
		true,
		false
	)
	if _game_mode == null:
		return

	if _game_mode.has_signal("mode_changed"):
		var callback := Callable(self, "_on_game_mode_changed")
		if not _game_mode.is_connected("mode_changed", callback):
			_game_mode.connect("mode_changed", callback)


func _on_game_mode_changed(_new_mode: int) -> void:
	# Messages from the previous context should not cross the camera/mode
	# transition. This also prevents a tween from finishing at the old layout.
	clear()
	_apply_layout_from_game_mode(false)


func _apply_layout_from_game_mode(reposition_visible: bool = true) -> void:
	var fishing := false
	if is_instance_valid(_game_mode) and _game_mode.has_method("is_fishing"):
		fishing = bool(_game_mode.call("is_fishing"))

	_using_fishing_layout = fishing
	_rest_position = (
		_fishing_rest_position
		if _using_fishing_layout
		else exploration_position
	)

	if reposition_visible or not root.visible:
		root.position = _rest_position
