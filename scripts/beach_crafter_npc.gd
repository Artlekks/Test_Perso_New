extends Node3D
class_name BeachCrafterNPC

@export var idle_animation: StringName = &"Bag_Search"
@export var talk_animation: StringName = &"Stand_Interest"
@export var interaction_prompt: String = "K : Craft"
@export var greeting_text: String = "Let's make something."
@export var card_opponent_id: StringName = &""
@export var card_opponent_profile: Resource

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var crafting_menu: BeachCraftingMenu = $BeachCraftingMenu

var _player_in_range: bool = false
var _crafting_service: BeachCraftingService = null
var _inventory: BeachGatheringInventory = null
var _cached_card_game: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_play_idle()
	prompt_label.visible = false
	prompt_label.text = interaction_prompt
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	call_deferred("_bind_crafting")


func _input(event: InputEvent) -> void:
	if crafting_menu != null and crafting_menu.is_open():
		return
	if not _player_in_range:
		return
	var tree := get_tree()
	if tree == null or tree.paused:
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
	if not _bind_crafting():
		return
	_play_talk()
	crafting_menu.open_menu()


func _bind_crafting() -> bool:
	var services := _find_session_services()
	if services == null:
		return false

	var raw_service = services.get("beach_crafting_service")
	var raw_inventory = services.get("beach_gathering_inventory")
	if raw_service is BeachCraftingService:
		_crafting_service = raw_service
	if raw_inventory is BeachGatheringInventory:
		_inventory = raw_inventory

	if _crafting_service == null or _inventory == null:
		return false
	crafting_menu.configure(_crafting_service, _inventory)
	return true


func _find_session_services() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var services := tree.root.get_node_or_null(
		"FishingSessionServices"
	)
	if services != null:
		return services

	var scene := tree.current_scene
	if scene == null:
		return null
	var fishing := scene.find_child("Fishing", true, false)
	if fishing != null:
		var candidate = fishing.get("session_services")
		if candidate is Node:
			return candidate
	return null


func _play_idle() -> void:
	_play_animation_if_available(idle_animation)


func _play_talk() -> void:
	_play_animation_if_available(talk_animation)


func _play_animation_if_available(animation_name: StringName) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return
	animated_sprite.play(animation_name)


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true
	prompt_label.visible = false


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	prompt_label.visible = false
	if crafting_menu == null or not crafting_menu.is_open():
		_play_idle()


func _is_player_body(body: Node) -> bool:
	return (
		body != null
		and body is CharacterBody3D
		and body.name == "CharacterBody3D"
	)


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
