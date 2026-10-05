extends Node3D
class_name FishingRewardClaimNPCBase

## Shared interaction/runtime plumbing for world NPCs that claim rewards from
## FishingRewardService. Reward logic stays in the concrete NPC/policy.

@export var interaction_prompt: String = "K : Talk"
@export var idle_animation: StringName = &"Stand_Interest"
@export var talk_animation: StringName = &"Bag_Search"
@export_range(0.25, 1.5, 0.05) var max_interaction_distance: float = 0.68

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea

var _player_in_range: bool = false
var _player: Node3D = null
var _reward_service: FishingRewardService = null
var _dialogue_service: Node = null
var _info_view: FishingInfoView = null


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
	if not _is_player_close_enough():
		return
	if not _bind_runtime():
		_show_message("The fishing reward service is not ready yet.", 2.5)
		return
	_on_reward_interaction()
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _on_reward_interaction() -> void:
	pass


func _bind_runtime() -> bool:
	var services := _find_session_services()
	if _reward_service != null:
		_bind_dialogue_runtime(services)
		if not is_instance_valid(_player):
			_player = _find_player()
		if not is_instance_valid(_info_view):
			_info_view = _find_info_view()
		return true

	if services == null:
		return false

	if services.has_method("get_fishing_reward_service"):
		var raw_reward = services.call("get_fishing_reward_service")
		if raw_reward is FishingRewardService:
			_reward_service = raw_reward
	if _reward_service == null:
		var raw_property = services.get("reward_service")
		if raw_property is FishingRewardService:
			_reward_service = raw_property

	_bind_dialogue_runtime(services)
	_player = _find_player()
	_info_view = _find_info_view()
	return _reward_service != null


func _find_session_services() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var services := tree.root.get_node_or_null("FishingSessionServices")
	if services != null:
		return services
	var scene := tree.current_scene
	if scene == null:
		return null
	var fishing := scene.find_child("Fishing", true, false)
	if fishing == null:
		return null
	var candidate = fishing.get("session_services")
	if candidate is Node:
		return candidate
	return null


func _bind_dialogue_runtime(services: Node) -> void:
	if is_instance_valid(_dialogue_service):
		return
	if services == null:
		return
	if services.has_method("get_dialogue_service"):
		var candidate = services.call("get_dialogue_service")
		if candidate is Node:
			_dialogue_service = candidate
			return
	var raw_property = services.get("dialogue_service")
	if raw_property is Node:
		_dialogue_service = raw_property


func _find_player() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var candidates := tree.get_nodes_in_group("fishing_player")
	if not candidates.is_empty() and candidates[0] is Node3D:
		return candidates[0] as Node3D
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.find_child("CharacterBody3D", true, false) as Node3D


func _find_info_view() -> FishingInfoView:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.find_child("FishingInfoView", true, false) as FishingInfoView


func _is_player_close_enough() -> bool:
	if not is_instance_valid(_player):
		_player = _find_player()
	if not is_instance_valid(_player):
		return false
	var offset := _player.global_position - global_position
	offset.y = 0.0
	return offset.length() <= max_interaction_distance


func _show_message(text: String, duration: float = 3.0) -> void:
	if not is_instance_valid(_info_view):
		_info_view = _find_info_view()
	if _info_view != null:
		_info_view.show_message(text, duration, FishingInfoView.Priority.IMPORTANT)


func _show_dialogue_line(
	speaker_id: StringName,
	speaker_name: String,
	text: String,
	fallback_duration: float = 3.0,
	dialogue_id: StringName = &"runtime_dialogue",
	portrait: Texture2D = null
) -> bool:
	if not is_instance_valid(_dialogue_service):
		_bind_dialogue_runtime(_find_session_services())
	if _dialogue_service != null and _dialogue_service.has_method("start_inline_dialogue"):
		var result = _dialogue_service.call(
			"start_inline_dialogue",
			dialogue_id,
			[{
				"speaker_id": speaker_id,
				"speaker_name": speaker_name,
				"portrait": portrait,
				"text": text,
			}],
			true,
			{},
			{"source_node": str(name)}
		)
		if result is Dictionary and bool(result.get("success", false)):
			return true
	var fallback_text := text
	if not speaker_name.is_empty():
		fallback_text = "%s: %s" % [speaker_name, text]
	_show_message(fallback_text, fallback_duration)
	return false


func _start_authored_dialogue(
	dialogue_id: StringName,
	fallback_speaker: String,
	fallback_text: String,
	fallback_duration: float = 3.0,
	portrait: Texture2D = null
) -> bool:
	if not is_instance_valid(_dialogue_service):
		_bind_dialogue_runtime(_find_session_services())
	if _dialogue_service != null and _dialogue_service.has_method("start_dialogue"):
		var result = _dialogue_service.call(
			"start_dialogue",
			dialogue_id,
			{},
			{
				"source_node": str(name),
				"portrait": portrait,
			}
		)
		if result is Dictionary and bool(result.get("success", false)):
			return true
	var fallback := fallback_text
	if not fallback_speaker.is_empty():
		fallback = "%s: %s" % [fallback_speaker, fallback_text]
	_show_message(fallback, fallback_duration)
	return false


func _play_animation(animation_name: StringName) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true
	_player = body as Node3D


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
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
