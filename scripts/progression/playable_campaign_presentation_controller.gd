extends Node
class_name PlayableCampaignPresentationController
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")

## Runtime bridge from the read-only Campaign Progression Director to the beach
## presentation layer. It does not unlock systems or mutate save data.
##
## V1 responsibilities:
## - suppress advanced prototype interaction prompts until their campaign stage;
## - never strand an already-active/available Regional Championship;
## - surface a few major progression changes through the existing info banner.

const PresentationPolicyScript = preload(
	"res://scripts/progression/playable_campaign_presentation_policy.gd"
)

const TARGET_NODE_NAMES := {
	"beach_trader": "TripleTriadOpponentNPC",
	"card_maker": "FishingCardMakerNPC",
	"harbor_request": "HarborRequestBoard",
	"harbor_lockbox": "HarborLockbox",
	"regional_championship": "RegionalChampionshipRegistrar",
}

@export var refresh_interval: float = 0.5

var _director = null
var _timer: Timer = null
var _last_snapshot: Dictionary = {}
var _last_feature_states: Dictionary = {}
var _info_view: Node = null
var _pending_message: Dictionary = {}
var _guidance_armed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_timer = Timer.new()
	_timer.name = "CampaignPresentationRefreshTimer"
	_timer.one_shot = false
	_timer.wait_time = maxf(0.2, refresh_interval)
	_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	add_child(_timer)
	_timer.timeout.connect(_refresh)
	_timer.start()

	var tree: SceneTree = get_tree()
	if tree != null:
		var callback := Callable(self, "_on_node_added")
		if not tree.is_connected("node_added", callback):
			tree.connect("node_added", callback)
	call_deferred("_refresh")
	var developer := RuntimeAccessPolicy.current()
	if developer != null: developer.mode_changed.connect(_on_developer_mode_changed)

func _on_developer_mode_changed(_enabled: bool) -> void:
	_apply_feature_states()


func configure(director) -> void:
	_director = director
	call_deferred("_refresh")


func refresh_now() -> void:
	_refresh()


func get_debug_snapshot() -> Dictionary:
	return {
		"feature_states": _last_feature_states.duplicate(true),
		"phase_id": str(_last_snapshot.get("phase_id", "")),
		"objective_code": str(
			_dict(_last_snapshot.get("next_objective", {})).get("code", "")
		),
		"info_view_bound": is_instance_valid(_info_view),
		"pending_message": _pending_message.duplicate(true),
		"guidance_armed": _guidance_armed,
	}


func _refresh() -> void:
	# Session services can configure this controller before it is attached to
	# the SceneTree. SceneTree APIs emit debugger errors in that bootstrap window.
	if not is_inside_tree():
		return
	_bind_info_view()
	if _director == null or not _director.has_method("get_snapshot"):
		return

	var raw_snapshot = _director.call("get_snapshot")
	if not (raw_snapshot is Dictionary):
		return
	var snapshot: Dictionary = (raw_snapshot as Dictionary).duplicate(true)
	var feature_states: Dictionary = PresentationPolicyScript.feature_states(
		snapshot
	)

	if feature_states != _last_feature_states:
		_last_feature_states = feature_states.duplicate(true)
		_apply_feature_states()

	var facts: Dictionary = _dict(snapshot.get("facts", {}))
	var backend_available: bool = bool(
		facts.get("card_backend_available", false)
	)
	if not backend_available:
		_last_snapshot = snapshot
		_guidance_armed = false
		return
	if not _guidance_armed:
		# Scene/session bootstrap can briefly report the card provider as absent.
		# Baseline the first fully-live snapshot so reloads do not replay old
		# discovery banners as though they just happened.
		_last_snapshot = snapshot
		_guidance_armed = true
		_flush_pending_message()
		return

	var message: Dictionary = PresentationPolicyScript.transition_message(
		_last_snapshot,
		snapshot
	)
	_last_snapshot = snapshot
	if not message.is_empty():
		_show_or_queue_message(message)
	_flush_pending_message()


func _apply_feature_states() -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null or GameplaySceneRoot.resolve(tree) == null:
		return
	for raw_feature_id in TARGET_NODE_NAMES.keys():
		var feature_id: String = str(raw_feature_id)
		var node_name: String = str(TARGET_NODE_NAMES[raw_feature_id])
		var target: Node = GameplaySceneRoot.resolve(tree).find_child(
			node_name,
			true,
			false
		)
		if target == null:
			continue
		_set_interaction_enabled(
			target,
			bool(_last_feature_states.get(feature_id, false))
		)


func _set_interaction_enabled(target: Node, enabled: bool) -> void:
	if target == null:
		return
	enabled = enabled or RuntimeAccessPolicy.allows(&"world_interactions")

	# Keep the world object/NPC visible and animated. Campaign staging only
	# controls whether it advertises/accepts its prototype interaction yet.
	target.set_process_input(enabled)
	target.set_process_unhandled_input(enabled)

	var prompt: Node = target.find_child("PromptLabel3D", true, false)
	if not enabled and prompt is Label3D:
		(prompt as Label3D).visible = false

	var area: Node = target.find_child("InteractionArea", true, false)
	if area is Area3D:
		(area as Area3D).set_deferred("monitoring", enabled)
		(area as Area3D).set_deferred("monitorable", enabled)


func _on_node_added(node: Node) -> void:
	if node == null:
		return
	if node.name == "FishingInfoView":
		_info_view = node
		_flush_pending_message()
		return
	for raw_feature_id in TARGET_NODE_NAMES.keys():
		var node_name: String = str(TARGET_NODE_NAMES[raw_feature_id])
		if node.name != node_name:
			continue
		var feature_id: String = str(raw_feature_id)
		_set_interaction_enabled(
			node,
			bool(_last_feature_states.get(feature_id, false))
		)
		return


func _bind_info_view() -> void:
	if is_instance_valid(_info_view):
		return
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null or GameplaySceneRoot.resolve(tree) == null:
		return
	var candidate: Node = GameplaySceneRoot.resolve(tree).find_child(
		"FishingInfoView",
		true,
		false
	)
	if candidate != null and candidate.has_method("show_message"):
		_info_view = candidate


func _show_or_queue_message(message: Dictionary) -> void:
	if message.is_empty():
		return
	if not is_instance_valid(_info_view):
		_pending_message = message.duplicate(true)
		return
	_info_view.call(
		"show_message",
		str(message.get("text", "")),
		float(message.get("duration", 3.0)),
		int(message.get("priority", 0))
	)


func _flush_pending_message() -> void:
	if _pending_message.is_empty() or not is_instance_valid(_info_view):
		return
	var message: Dictionary = _pending_message.duplicate(true)
	_pending_message.clear()
	_show_or_queue_message(message)


func _dict(value) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}
