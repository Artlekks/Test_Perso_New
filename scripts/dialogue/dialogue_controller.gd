extends Node
class_name DialogueController

## Owns dialogue input and pause ownership. The service remains pure state;
## the view remains presentation-only.

const DialogueViewScene = preload("res://actors/DialogueView.tscn")

var _service: DialogueService = null
var _view: DialogueView = null
var _opened_process_frame: int = -1
var _pause_owned: bool = false
var _previous_tree_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(service: DialogueService) -> void:
	if _service == service:
		_ensure_view()
		return
	_disconnect_service()
	_service = service
	_ensure_view()
	if _service == null:
		return
	_service.dialogue_started.connect(_on_dialogue_started)
	_service.line_changed.connect(_on_line_changed)
	_service.dialogue_finished.connect(_on_dialogue_finished)
	if _service.is_active():
		_on_dialogue_started(_service.get_snapshot())


func get_view() -> DialogueView:
	_ensure_view()
	return _view


func _input(event: InputEvent) -> void:
	if _service == null or not _service.is_active():
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	# Do not consume the K press that opened the dialogue if this controller is
	# later in the same input traversal than the NPC that started it.
	if Engine.get_process_frames() == _opened_process_frame:
		return

	var snapshot := _service.get_snapshot()
	var has_choices := bool(snapshot.get("has_choices", false))
	var handled := false
	if _is_key(key_event, KEY_K) or _is_key(key_event, KEY_ENTER):
		if has_choices:
			_service.select_choice()
		else:
			_service.advance()
		handled = true
	elif has_choices and (
		_is_key(key_event, KEY_W)
		or _is_key(key_event, KEY_UP)
	):
		_service.move_choice(-1)
		handled = true
	elif has_choices and (
		_is_key(key_event, KEY_S)
		or _is_key(key_event, KEY_DOWN)
	):
		_service.move_choice(1)
		handled = true
	elif _is_key(key_event, KEY_I) or _is_key(key_event, KEY_ESCAPE):
		_service.cancel(&"cancelled")
		handled = true
	else:
		# Dialogue owns keyboard focus while active. World systems are paused, and
		# this prevents ALWAYS-processing debug/NPC listeners from stealing keys.
		handled = true

	if handled:
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _on_dialogue_started(snapshot: Dictionary) -> void:
	_opened_process_frame = Engine.get_process_frames()
	_ensure_view()
	if _view != null:
		_view.present(snapshot)
	var tree := get_tree()
	if tree == null:
		return
	_previous_tree_paused = tree.paused
	if not tree.paused:
		tree.paused = true
		_pause_owned = true
	else:
		_pause_owned = false


func _on_line_changed(snapshot: Dictionary) -> void:
	_ensure_view()
	if _view != null:
		_view.present(snapshot)


func _on_dialogue_finished(_dialogue_id: StringName, _reason: StringName) -> void:
	if _view != null:
		_view.hide_dialogue()
	_restore_pause_state()


func _ensure_view() -> void:
	if is_instance_valid(_view):
		return
	var instance = DialogueViewScene.instantiate()
	if not (instance is DialogueView):
		push_error("DialogueController: DialogueView.tscn root is not DialogueView.")
		instance.free()
		return
	_view = instance as DialogueView
	_view.name = "DialogueView"
	add_child(_view)


func _disconnect_service() -> void:
	if _service == null:
		return
	var started_callable := Callable(self, "_on_dialogue_started")
	var line_callable := Callable(self, "_on_line_changed")
	var finished_callable := Callable(self, "_on_dialogue_finished")
	if _service.dialogue_started.is_connected(started_callable):
		_service.dialogue_started.disconnect(started_callable)
	if _service.line_changed.is_connected(line_callable):
		_service.line_changed.disconnect(line_callable)
	if _service.dialogue_finished.is_connected(finished_callable):
		_service.dialogue_finished.disconnect(finished_callable)


func _restore_pause_state() -> void:
	var tree := get_tree()
	if tree != null and _pause_owned:
		tree.paused = _previous_tree_paused
	_pause_owned = false
	_previous_tree_paused = false


func _exit_tree() -> void:
	_restore_pause_state()
	_disconnect_service()


func _is_key(event: InputEventKey, key: Key) -> bool:
	return event.keycode == key or event.physical_keycode == key
