extends Node
class_name DialogueNPCBridge

## Small reusable adapter between an NPC interaction and DialogueService.
##
## The bridge owns no gameplay/menu logic. It starts one dialogue and reports
## how that dialogue ended. The NPC remains responsible for what happens after
## completion (open a shop, open crafting, start a card maker menu, etc.).

signal interaction_finished(action_id: StringName, reason: StringName)

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
	if dialogue_id == &"" or text.strip_edges().is_empty():
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
		[{
			"speaker_id": speaker_id,
			"speaker_name": speaker_name,
			"portrait": portrait,
			"text": text,
		}],
		allow_cancel,
		{},
		payload
	)
	if not (result is Dictionary) or not bool(result.get("success", false)):
		return false

	_pending_dialogue_id = dialogue_id
	_pending_action_id = action_id
	return true


func cancel_pending() -> void:
	_pending_dialogue_id = &""
	_pending_action_id = &""


func _connect_service() -> void:
	if _service == null or not _service.has_signal("dialogue_finished"):
		return
	var callback := Callable(self, "_on_dialogue_finished")
	if not _service.is_connected("dialogue_finished", callback):
		_service.connect("dialogue_finished", callback)


func _disconnect_service() -> void:
	if _service == null or not is_instance_valid(_service):
		_service = null
		return
	if _service.has_signal("dialogue_finished"):
		var callback := Callable(self, "_on_dialogue_finished")
		if _service.is_connected("dialogue_finished", callback):
			_service.disconnect("dialogue_finished", callback)
	_service = null


func _on_dialogue_finished(dialogue_id: StringName, reason: StringName) -> void:
	if dialogue_id != _pending_dialogue_id:
		return
	var action_id := _pending_action_id
	_pending_dialogue_id = &""
	_pending_action_id = &""
	interaction_finished.emit(action_id, reason)


func _find_dialogue_service() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var services := tree.root.get_node_or_null("FishingSessionServices")
	if services == null:
		var scene := tree.current_scene
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
	_disconnect_service()
