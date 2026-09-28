extends Node3D

@export var interaction_prompt: String = "K : Cards"
@export var opponent_profile: Resource

@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea

var _player_in_range: bool = false
var _cached_game: Node = null


func _ready() -> void:
	prompt_label.visible = false
	prompt_label.text = interaction_prompt
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)


func _input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return
	if not _is_confirm(event):
		return
	var game: Node = _find_game()
	if game != null and game.has_method("open_game"):
		game.call("open_game", opponent_profile)
	get_viewport().set_input_as_handled()


func _find_game() -> Node:
	if is_instance_valid(_cached_game):
		return _cached_game
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	_cached_game = scene.find_child("TripleTriadGame", true, false)
	return _cached_game


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true
	prompt_label.visible = true


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	prompt_label.visible = false


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
