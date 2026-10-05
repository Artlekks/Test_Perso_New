extends Node3D

const PRIMARY_INTERACTION_GROUP: StringName = &"beach_trade_craft_interactable"

@export_range(0.2, 1.2, 0.02) var max_interaction_distance: float = 0.62
@export var idle_animation: StringName = &"Bag_Search"
@export var talk_animation: StringName = &"Stand_Interest"
@export var interaction_prompt: String = "K : Trade"
@export var greeting_text: String = "Take a look."
@export var card_opponent_id: StringName = &""
@export var card_opponent_profile: Resource

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea

var _player_in_range: bool = false
var _player_body: CharacterBody3D = null
var _cached_menu: Node = null
var _cached_card_game: Node = null


func _ready() -> void:
	add_to_group(PRIMARY_INTERACTION_GROUP)
	_play_idle()
	prompt_label.visible = false
	prompt_label.text = interaction_prompt
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)


func _input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	if not _can_player_interact_now():
		return
	if get_tree() == null or get_tree().paused:
		return

	if _is_card_action(event):
		if _start_card_interaction():
			get_viewport().set_input_as_handled()
		return

	if not _is_confirm(event):
		return
	_start_interaction()
	get_viewport().set_input_as_handled()


func _start_interaction() -> void:
	_play_talk()
	var target_menu: Node = _find_economy_menu()
	if target_menu != null and target_menu.has_method("open_menu"):
		target_menu.call("open_menu")


func _play_idle() -> void:
	_play_animation_if_available(idle_animation)


func _play_talk() -> void:
	_play_animation_if_available(talk_animation)


func _play_animation_if_available(animation_name: StringName) -> void:
	if animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		push_warning("BeachMerchantNPC: missing animation '%s'." % String(animation_name))
		return
	animated_sprite.play(animation_name)


func _find_economy_menu() -> Node:
	if is_instance_valid(_cached_menu):
		return _cached_menu
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	_cached_menu = scene.find_child("FishingEconomyMenu", true, false)
	return _cached_menu


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true
	_player_body = body as CharacterBody3D
	prompt_label.visible = false


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	if body == _player_body:
		_player_body = null
	prompt_label.visible = false
	_play_idle()


func _can_player_interact_now() -> bool:
	if not is_instance_valid(_player_body):
		return false
	if get_player_interaction_distance() > max_interaction_distance:
		return false
	return _is_nearest_primary_interactable()


func get_player_interaction_distance() -> float:
	if not is_instance_valid(_player_body):
		return INF
	var npc_flat: Vector2 = Vector2(global_position.x, global_position.z)
	var player_flat: Vector2 = Vector2(
		_player_body.global_position.x,
		_player_body.global_position.z
	)
	return npc_flat.distance_to(player_flat)


func _is_nearest_primary_interactable() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return true

	var my_distance: float = get_player_interaction_distance()
	for candidate: Node in tree.get_nodes_in_group(PRIMARY_INTERACTION_GROUP):
		if candidate == self:
			continue
		if not candidate.has_method("get_player_interaction_distance"):
			continue

		var other_distance: float = float(
			candidate.call("get_player_interaction_distance")
		)
		var other_limit: float = max_interaction_distance
		var raw_limit: Variant = candidate.get("max_interaction_distance")
		if raw_limit is float or raw_limit is int:
			other_limit = float(raw_limit)

		if (
			other_distance <= other_limit
			and other_distance + 0.01 < my_distance
		):
			return false

	return true


func _is_player_body(body: Node) -> bool:
	return body != null and body is CharacterBody3D and body.name == "CharacterBody3D"


func _start_card_interaction() -> bool:
	if (
		card_opponent_id == &""
		and card_opponent_profile == null
	):
		return false

	var game: Node = _find_card_game()
	if game == null:
		return false

	if (
		card_opponent_id != &""
		and game.has_method("open_game_by_id")
	):
		game.call("open_game_by_id", card_opponent_id)
		return true

	if game.has_method("open_game"):
		game.call("open_game", card_opponent_profile)
		return true

	return false


func _find_card_game() -> Node:
	if is_instance_valid(_cached_card_game):
		return _cached_card_game

	var scene: Node = get_tree().current_scene
	if scene == null:
		return null

	_cached_card_game = scene.find_child(
		"TripleTriadGame",
		true,
		false
	)
	return _cached_card_game


func _is_card_action(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return (
		key_event.pressed
		and not key_event.echo
		and (
			key_event.keycode == KEY_C
			or key_event.physical_keycode == KEY_C
		)
	)


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
