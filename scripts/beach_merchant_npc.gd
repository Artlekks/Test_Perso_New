extends Node3D

@export var idle_animation: StringName = &"Bag_Search"
@export var talk_animation: StringName = &"Stand_Interest"
@export var interaction_prompt: String = "K : Trade"
@export var greeting_text: String = "Take a look."

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea

var _player_in_range: bool = false
var _cached_menu: Node = null


func _ready() -> void:
	_play_idle()
	prompt_label.visible = false
	prompt_label.text = interaction_prompt
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)


func _input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	if get_tree() == null or get_tree().paused:
		return
	if not _is_confirm(event):
		return
	_start_interaction()
	get_viewport().set_input_as_handled()


func _start_interaction() -> void:
	_play_talk()
	var target_menu: Node = _find_economy_menu()
	if target_menu != null and target_menu.has_method("open_menu"):
		prompt_label.text = greeting_text
		target_menu.call("open_menu")
	else:
		prompt_label.text = interaction_prompt


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
	prompt_label.text = interaction_prompt
	prompt_label.visible = true


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	prompt_label.visible = false
	prompt_label.text = interaction_prompt
	_play_idle()


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
