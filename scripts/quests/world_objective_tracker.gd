extends CanvasLayer
class_name WorldObjectiveTracker
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")

## Lightweight exploration objective tracker + request read model.
##
## Request/gameplay owners register already-resolved presentation snapshots.
## This node chooses one primary active request for the exploration HUD and
## keeps accepted/ready/completed snapshots available to the read-only journal.
## It never accepts quests, completes objectives, grants rewards, or writes saves.

const WorldRequestJournalScene = preload("res://actors/WorldRequestJournal.tscn")
const WorldRequestRegistryScript = preload("res://scripts/quests/world_request_registry.gd")

@export var game_mode_node_name: StringName = &"GameMode"

@onready var root: Control = $Root
@onready var title_label: Label = $Root/Panel/TitleLabel
@onready var status_label: Label = $Root/Panel/StatusLabel
@onready var objective_label: Label = $Root/Panel/ObjectiveLabel

var _requests: Dictionary = {}
var _primary_snapshot: Dictionary = {}
var _game_mode: Node = null
var _journal_view: Node = null


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
	state_id: StringName,
	metadata: Dictionary = {}
) -> void:
	var key := String(request_id)
	if not should_keep_journal_state(state_id):
		_requests.erase(key)
		_refresh_primary()
		return

	var canonical := WorldRequestRegistryScript.presentation_for(
		request_id,
		state_id,
		objective
	)
	var canonical_metadata: Dictionary = {}
	var raw_canonical_metadata = canonical.get("metadata", {})
	if raw_canonical_metadata is Dictionary:
		canonical_metadata = (raw_canonical_metadata as Dictionary).duplicate(true)
	for raw_key in metadata.keys():
		canonical_metadata[raw_key] = metadata[raw_key]

	var resolved_title := str(canonical.get("title", title))
	if resolved_title.strip_edges().is_empty():
		resolved_title = title
	var resolved_objective := str(canonical.get("objective", objective))
	if resolved_objective.strip_edges().is_empty():
		resolved_objective = objective

	_requests[key] = {
		"request_id": request_id,
		"title": resolved_title,
		"objective": resolved_objective,
		"state_id": state_id,
		"priority": priority_for_state(state_id),
		"journal_priority": journal_priority_for_state(state_id),
		"sort_order": int(canonical.get("sort_order", 1000)),
		"metadata": canonical_metadata,
	}
	_refresh_primary()


func register_request_state(
	request_id: StringName,
	objective: String,
	state_id: StringName,
	metadata: Dictionary = {}
) -> void:
	var canonical := WorldRequestRegistryScript.presentation_for(
		request_id,
		state_id,
		objective
	)
	var resolved_title := str(canonical.get("title", ""))
	if resolved_title.strip_edges().is_empty():
		resolved_title = "Request"
	register_request(
		request_id,
		resolved_title,
		str(canonical.get("objective", objective)),
		state_id,
		metadata
	)


func remove_request(request_id: StringName) -> void:
	_requests.erase(String(request_id))
	_refresh_primary()


func has_request(request_id: StringName) -> bool:
	return _requests.has(String(request_id))


func get_primary_snapshot() -> Dictionary:
	return _primary_snapshot.duplicate(true)


func get_registered_request_count() -> int:
	return _requests.size()


func get_journal_snapshots() -> Array:
	return sort_journal_snapshots(_requests)


func has_journal_entries() -> bool:
	return not get_journal_snapshots().is_empty()


func open_journal() -> bool:
	if not is_inside_tree():
		return false
	var tree := get_tree()
	if tree == null or GameplaySceneRoot.resolve(tree) == null:
		return false

	if not is_instance_valid(_journal_view):
		var existing := GameplaySceneRoot.resolve(tree).find_child(
			"WorldRequestJournal",
			true,
			false
		)
		if existing != null and existing.has_method("open_with_requests"):
			_journal_view = existing
		else:
			_journal_view = WorldRequestJournalScene.instantiate()
			if _journal_view == null:
				return false
			GameplaySceneRoot.resolve(tree).add_child(_journal_view)

	if not _journal_view.has_method("open_with_requests"):
		return false
	_journal_view.call("open_with_requests", get_journal_snapshots())
	return true


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
	_refresh_visibility()


static func should_track_state(state_id: StringName) -> bool:
	return state_id == &"accepted" or state_id == &"ready_to_turn_in"


static func should_keep_journal_state(state_id: StringName) -> bool:
	return (
		state_id == &"accepted"
		or state_id == &"ready_to_turn_in"
		or state_id == &"completed"
	)


static func priority_for_state(state_id: StringName) -> int:
	match state_id:
		&"ready_to_turn_in":
			return 20
		&"accepted":
			return 10
	return -1


static func journal_priority_for_state(state_id: StringName) -> int:
	match state_id:
		&"ready_to_turn_in":
			return 30
		&"accepted":
			return 20
		&"completed":
			return 10
	return -1


static func status_text(state_id: StringName) -> String:
	if state_id == &"ready_to_turn_in":
		return "READY"
	if state_id == &"accepted":
		return "ACTIVE"
	if state_id == &"completed":
		return "COMPLETE"
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
		var sort_order := int(snapshot.get("sort_order", 1000))
		var best_sort_order := int(best.get("sort_order", 1000)) if not best.is_empty() else 1000
		if priority > best_priority or (
			priority == best_priority
			and (
				best_id.is_empty()
				or sort_order < best_sort_order
				or (sort_order == best_sort_order and key < best_id)
			)
		):
			best = snapshot.duplicate(true)
			best_priority = priority
			best_id = key
	return best


static func sort_journal_snapshots(requests: Dictionary) -> Array:
	var snapshots: Array = []
	for raw_key in requests.keys():
		var raw_snapshot = requests.get(raw_key, {})
		if not (raw_snapshot is Dictionary):
			continue
		var snapshot: Dictionary = (raw_snapshot as Dictionary).duplicate(true)
		var state_id := StringName(str(snapshot.get("state_id", "")))
		if not should_keep_journal_state(state_id):
			continue
		snapshot["journal_priority"] = int(
			snapshot.get(
				"journal_priority",
				journal_priority_for_state(state_id)
			)
		)
		snapshots.append(snapshot)

	# Small deterministic insertion sort avoids coupling the resource to a
	# callable/lambda comparator and keeps ordering easy to audit in QA.
	for index in range(1, snapshots.size()):
		var candidate: Dictionary = snapshots[index]
		var cursor := index - 1
		while cursor >= 0:
			var current: Dictionary = snapshots[cursor]
			if not _journal_snapshot_before(candidate, current):
				break
			snapshots[cursor + 1] = current
			cursor -= 1
		snapshots[cursor + 1] = candidate
	return snapshots


static func _journal_snapshot_before(a: Dictionary, b: Dictionary) -> bool:
	var a_priority := int(a.get("journal_priority", -1))
	var b_priority := int(b.get("journal_priority", -1))
	if a_priority != b_priority:
		return a_priority > b_priority
	var a_sort_order := int(a.get("sort_order", 1000))
	var b_sort_order := int(b.get("sort_order", 1000))
	if a_sort_order != b_sort_order:
		return a_sort_order < b_sort_order
	var a_title := str(a.get("title", ""))
	var b_title := str(b.get("title", ""))
	if a_title != b_title:
		return a_title.naturalnocasecmp_to(b_title) < 0
	return str(a.get("request_id", "")) < str(b.get("request_id", ""))
