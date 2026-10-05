extends CanvasLayer
class_name WorldObjectiveTracker

## Lightweight exploration objective tracker.
##
## Request/gameplay owners register already-resolved presentation snapshots.
## This view chooses one primary request deterministically and renders it. It
## never accepts quests, completes objectives, grants rewards, or writes saves.

@export var game_mode_node_name: StringName = &"GameMode"

@onready var root: Control = $Root
@onready var title_label: Label = $Root/Panel/TitleLabel
@onready var status_label: Label = $Root/Panel/StatusLabel
@onready var objective_label: Label = $Root/Panel/ObjectiveLabel

var _requests: Dictionary = {}
var _primary_snapshot: Dictionary = {}
var _game_mode: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	_bind_game_mode()
	_refresh_primary()
	set_process(true)


func _process(_delta: float) -> void:
	if not is_instance_valid(_game_mode):
		_bind_game_mode()
	_refresh_visibility()


func register_request(
	request_id: StringName,
	title: String,
	objective: String,
	state_id: StringName
) -> void:
	var key := String(request_id)
	if not should_track_state(state_id):
		_requests.erase(key)
		_refresh_primary()
		return

	_requests[key] = {
		"request_id": request_id,
		"title": title,
		"objective": objective,
		"state_id": state_id,
		"priority": priority_for_state(state_id),
	}
	_refresh_primary()


func remove_request(request_id: StringName) -> void:
	_requests.erase(String(request_id))
	_refresh_primary()


func has_request(request_id: StringName) -> bool:
	return _requests.has(String(request_id))


func get_primary_snapshot() -> Dictionary:
	return _primary_snapshot.duplicate(true)


func get_registered_request_count() -> int:
	return _requests.size()


func _refresh_primary() -> void:
	_primary_snapshot = select_primary(_requests)
	if not is_node_ready():
		return

	if _primary_snapshot.is_empty():
		root.visible = false
		return

	title_label.text = str(_primary_snapshot.get("title", "Request"))
	status_label.text = status_text(
		StringName(str(_primary_snapshot.get("state_id", "accepted")))
	)
	objective_label.text = str(_primary_snapshot.get("objective", ""))
	_refresh_visibility()


func _refresh_visibility() -> void:
	if not is_node_ready():
		return
	root.visible = (
		not _primary_snapshot.is_empty()
		and _presentation_allowed()
	)


func _presentation_allowed() -> bool:
	var tree := get_tree()
	if tree != null and tree.paused:
		return false

	if is_instance_valid(_game_mode) and _game_mode.has_method("is_fishing"):
		if bool(_game_mode.call("is_fishing")):
			return false
	return true


func _bind_game_mode() -> void:
	if is_instance_valid(_game_mode):
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	_game_mode = tree.current_scene.find_child(
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
	_refresh_visibility()


static func should_track_state(state_id: StringName) -> bool:
	return state_id == &"accepted" or state_id == &"ready_to_turn_in"


static func priority_for_state(state_id: StringName) -> int:
	match state_id:
		&"ready_to_turn_in":
			return 20
		&"accepted":
			return 10
	return -1


static func status_text(state_id: StringName) -> String:
	if state_id == &"ready_to_turn_in":
		return "READY"
	if state_id == &"accepted":
		return "ACTIVE"
	return ""


static func select_primary(requests: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_priority := -999999
	var best_id := ""

	var keys: Array = requests.keys()
	keys.sort()
	for raw_key in keys:
		var key := str(raw_key)
		var raw_snapshot = requests.get(raw_key, {})
		if not (raw_snapshot is Dictionary):
			continue
		var snapshot: Dictionary = raw_snapshot
		var state_id := StringName(str(snapshot.get("state_id", "")))
		if not should_track_state(state_id):
			continue
		var priority := int(
			snapshot.get("priority", priority_for_state(state_id))
		)
		if priority > best_priority or (
			priority == best_priority and (best_id.is_empty() or key < best_id)
		):
			best = snapshot.duplicate(true)
			best_priority = priority
			best_id = key
	return best
