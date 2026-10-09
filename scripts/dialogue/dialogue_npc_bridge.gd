extends Node
class_name DialogueNPCBridge
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")

## Small reusable adapter between an NPC interaction and DialogueService.
##
## The bridge owns no gameplay/menu logic. It starts dialogue and reports how
## that dialogue ended. For choice prompts it also reports the selected stable
## choice id. The NPC remains responsible for what happens after completion.

signal interaction_finished(action_id: StringName, reason: StringName)
signal choice_made(
	action_id: StringName,
	choice_id: StringName,
	choice_metadata: Dictionary
)

var _service: Node = null
var _pending_dialogue_id: StringName = &""
var _pending_action_id: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure_service(service: Node) -> void:
	if _service == service:
		return
	_disconnect_service()
	_service = service
	_connect_service()


func bind_from_session() -> bool:
	if is_instance_valid(_service):
		return true
	var service := _find_dialogue_service()
	if service == null:
		return false
	configure_service(service)
	return true


func start_single_line(
	dialogue_id: StringName,
	action_id: StringName,
	speaker_id: StringName,
	speaker_name: String,
	text: String,
	portrait: Texture2D = null,
	allow_cancel: bool = true,
	metadata: Dictionary = {}
) -> bool:
	return _start_inline_interaction(
		dialogue_id,
		action_id,
		[{
			"speaker_id": speaker_id,
			"speaker_name": speaker_name,
			"portrait": portrait,
			"text": text,
		}],
		allow_cancel,
		metadata
	)


func start_choice_prompt(
	dialogue_id: StringName,
	action_id: StringName,
	speaker_id: StringName,
	speaker_name: String,
	text: String,
	choices: Array,
	portrait: Texture2D = null,
	allow_cancel: bool = true,
	metadata: Dictionary = {}
) -> bool:
	if choices.is_empty():
		return false
	return _start_inline_interaction(
		dialogue_id,
		action_id,
		[{
			"speaker_id": speaker_id,
			"speaker_name": speaker_name,
			"portrait": portrait,
			"text": text,
			"choices": choices,
		}],
		allow_cancel,
		metadata
	)


func start_lines(
	dialogue_id: StringName,
	action_id: StringName,
	lines: Array,
	allow_cancel: bool = true,
	metadata: Dictionary = {}
) -> bool:
	if lines.is_empty():
		return false
	return _start_inline_interaction(
		dialogue_id,
		action_id,
		lines,
		allow_cancel,
		metadata
	)


func cancel_pending() -> void:
	_pending_dialogue_id = &""
	_pending_action_id = &""


func has_pending_interaction() -> bool:
	return _pending_dialogue_id != &""


func _start_inline_interaction(
	dialogue_id: StringName,
	action_id: StringName,
	lines: Array,
	allow_cancel: bool,
	metadata: Dictionary
) -> bool:
	if dialogue_id == &"" or lines.is_empty():
		return false
	if not bind_from_session():
		return false
	if not _service.has_method("start_inline_dialogue"):
		return false
	if _service.has_method("is_active") and bool(_service.call("is_active")):
		return false

	var payload := metadata.duplicate(true)
	payload["source_node"] = str(get_parent().name if get_parent() != null else name)
	var result = _service.call(
		"start_inline_dialogue",
		dialogue_id,
		lines,
		allow_cancel,
		{},
		payload
	)
	if not (result is Dictionary) or not bool(result.get("success", false)):
		return false

	_pending_dialogue_id = dialogue_id
	_pending_action_id = action_id
	return true


func _connect_service() -> void:
	if _service == null:
		return
	if _service.has_signal("dialogue_finished"):
		var finished_callback := Callable(self, "_on_dialogue_finished")
		if not _service.is_connected("dialogue_finished", finished_callback):
			_service.connect("dialogue_finished", finished_callback)
	if _service.has_signal("choice_selected"):
		var choice_callback := Callable(self, "_on_choice_selected")
		if not _service.is_connected("choice_selected", choice_callback):
			_service.connect("choice_selected", choice_callback)


func _disconnect_service() -> void:
	if _service == null or not is_instance_valid(_service):
		_service = null
		return
	if _service.has_signal("dialogue_finished"):
		var finished_callback := Callable(self, "_on_dialogue_finished")
		if _service.is_connected("dialogue_finished", finished_callback):
			_service.disconnect("dialogue_finished", finished_callback)
	if _service.has_signal("choice_selected"):
		var choice_callback := Callable(self, "_on_choice_selected")
		if _service.is_connected("choice_selected", choice_callback):
			_service.disconnect("choice_selected", choice_callback)
	_service = null


func _on_dialogue_finished(dialogue_id: StringName, reason: StringName) -> void:
	if dialogue_id != _pending_dialogue_id:
		return
	# Choice selection emits dialogue_finished first so the controller can release
	# pause ownership. Keep the pending ids until the following choice_selected
	# signal reports which choice was actually picked.
	if reason == &"choice_selected":
		return
	var action_id := _pending_action_id
	_pending_dialogue_id = &""
	_pending_action_id = &""
	interaction_finished.emit(action_id, reason)


func _on_choice_selected(
	dialogue_id: StringName,
	choice_id: StringName,
	choice_metadata: Dictionary
) -> void:
	if dialogue_id != _pending_dialogue_id:
		return
	var action_id := _pending_action_id
	_pending_dialogue_id = &""
	_pending_action_id = &""
	choice_made.emit(action_id, choice_id, choice_metadata.duplicate(true))
	interaction_finished.emit(action_id, &"choice_selected")


func _find_dialogue_service() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var services := tree.root.get_node_or_null("FishingSessionServices")
	if services == null:
		var scene := GameplaySceneRoot.resolve(tree)
		if scene != null:
			var fishing := scene.find_child("Fishing", true, false)
			if fishing != null:
				var candidate = fishing.get("session_services")
				if candidate is Node:
					services = candidate
	if services == null:
		return null
	if services.has_method("get_dialogue_service"):
		var resolved = services.call("get_dialogue_service")
		if resolved is Node:
			return resolved
	var raw = services.get("dialogue_service")
	if raw is Node:
		return raw
	return null


func _exit_tree() -> void:
	var service := _service
	var dialogue_id := _pending_dialogue_id
	# Disconnect before closing: teardown must not dispatch NPC actions back
	# into the actor that is leaving the scene.
	_disconnect_service()
	cancel_pending()
	if is_instance_valid(service) and dialogue_id != &"" and service.has_method("get_snapshot"):
		var snapshot: Dictionary = service.get_snapshot()
		if snapshot.get("active", false) and snapshot.get("dialogue_id", &"") == dialogue_id:
			service.force_close(&"source_removed")
