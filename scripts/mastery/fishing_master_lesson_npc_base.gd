extends Node3D
class_name FishingMasterLessonNPCBase

const DialogueNPCBridgeScript = preload("res://scripts/dialogue/dialogue_npc_bridge.gd")
const NPCDialogueRouterScript = preload("res://scripts/dialogue/npc_dialogue_router.gd")

## Shared runtime/interaction plumbing for fishing-master NPC lessons.
## Individual masters only own their lesson state and success condition.

@export var interaction_prompt: String = "K : Listen"
@export var idle_animation: StringName = &"Stand_Interest"
@export var talk_animation: StringName = &"Bag_Search"

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea

var _player_in_range: bool = false
var _player: Node = null
var _mastery_service: FishingMasteryService = null
var _info_view: FishingInfoView = null
var _dialogue_bridge: Node = null
var _interaction_dialogue_mode: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if prompt_label != null:
		prompt_label.text = interaction_prompt
		prompt_label.visible = false
	_play_animation(idle_animation)
	if interaction_area != null:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)
	call_deferred("_bind_runtime")


func _input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	if not _is_confirm(event):
		return
	_interaction_dialogue_mode = true
	_handle_interaction()
	_interaction_dialogue_mode = false
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func get_technique_id() -> StringName:
	return &""


func get_teacher_id() -> StringName:
	return &""


func get_known_message() -> String:
	return "You already know this lesson."


func get_unavailable_message() -> String:
	return "Come back when the water is ready."


func _on_lesson_interaction() -> void:
	pass


func _on_player_left_range() -> void:
	pass


func _handle_interaction() -> void:
	if not _bind_runtime():
		_show_message(get_unavailable_message(), 2.2)
		return
	if is_technique_known():
		_play_animation(talk_animation)
		_show_message(get_known_message(), 3.4)
		return
	_on_lesson_interaction()


func _bind_runtime() -> bool:
	if _mastery_service != null:
		if not is_instance_valid(_player):
			_player = _find_player()
		if not is_instance_valid(_info_view):
			_info_view = _find_info_view()
		return true

	var tree := get_tree()
	if tree == null:
		return false
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
		return false

	if services.has_method("get_fishing_mastery_service"):
		var raw_mastery = services.call("get_fishing_mastery_service")
		if raw_mastery is FishingMasteryService:
			_mastery_service = raw_mastery
	if _mastery_service == null:
		var raw_mastery_property = services.get("mastery_service")
		if raw_mastery_property is FishingMasteryService:
			_mastery_service = raw_mastery_property

	_player = _find_player()
	_info_view = _find_info_view()
	return _mastery_service != null


func is_technique_known() -> bool:
	return (
		_mastery_service != null
		and get_technique_id() != &""
		and _mastery_service.has_technique(get_technique_id())
	)


func try_learn_technique(persist: bool = true) -> Dictionary:
	if _mastery_service == null:
		return {"success": false, "reason": "mastery_unavailable"}
	return _mastery_service.learn_technique(
		get_technique_id(),
		get_teacher_id(),
		persist
	)


func _find_player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var candidates := tree.get_nodes_in_group("fishing_player")
	if not candidates.is_empty():
		return candidates[0] as Node
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.find_child("CharacterBody3D", true, false)


func _find_info_view() -> FishingInfoView:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	var candidate := tree.current_scene.find_child("FishingInfoView", true, false)
	return candidate as FishingInfoView


func _find_fishing_root() -> Node:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.find_child("Fishing", true, false)


func _show_message(text: String, duration: float = 3.0) -> void:
	# Direct player-to-master speech belongs in the dialogue box. Messages that
	# happen later during the live lesson remain HUD coaching so they never pause
	# a cast/fight just to display feedback.
	if _interaction_dialogue_mode and _show_npc_dialogue(text):
		return
	if not is_instance_valid(_info_view):
		_info_view = _find_info_view()
	if _info_view != null:
		_info_view.show_message(text, duration, FishingInfoView.Priority.IMPORTANT)


func _show_npc_dialogue(text: String) -> bool:
	var bridge := _ensure_dialogue_bridge()
	if bridge == null:
		return false
	var teacher_id := get_teacher_id()
	var dialogue_key := str(teacher_id)
	if dialogue_key.is_empty():
		dialogue_key = str(name).to_snake_case()
	var fallback_name: String = NPCDialogueRouterScript.humanize_id(
		teacher_id,
		"master_",
		"Fishing Master"
	)
	return NPCDialogueRouterScript.start_spoken_line(
		bridge,
		StringName("master_talk_%s" % dialogue_key),
		&"",
		teacher_id,
		fallback_name,
		text,
		animated_sprite,
		true,
		{"source": "fishing_master"}
	)


func _ensure_dialogue_bridge() -> Node:
	if is_instance_valid(_dialogue_bridge):
		return _dialogue_bridge
	_dialogue_bridge = DialogueNPCBridgeScript.new()
	_dialogue_bridge.name = "DialogueNPCBridge"
	add_child(_dialogue_bridge)
	return _dialogue_bridge


func _play_animation(animation_name: StringName) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true
	_player = body
	if prompt_label != null:
		prompt_label.visible = false


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	_on_player_left_range()
	_play_animation(idle_animation)


func _is_player_body(body: Node) -> bool:
	return body != null and body is CharacterBody3D and body.name == "CharacterBody3D"


func _is_confirm(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return (
		key_event.pressed
		and not key_event.echo
		and (
			key_event.keycode == KEY_K
			or key_event.physical_keycode == KEY_K
			or key_event.keycode == KEY_ENTER
			or key_event.physical_keycode == KEY_ENTER
		)
	)
