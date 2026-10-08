extends Node3D
class_name BeachCrafterNPC
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")

const DialogueNPCBridgeScript = preload("res://scripts/dialogue/dialogue_npc_bridge.gd")
const PORTRAIT: Texture2D = preload("res://data/dialogue/portraits/beach_crafter.tres")
const DIALOGUE_ID: StringName = &"beach_crafter_services"
const EXPLANATION_DIALOGUE_ID: StringName = &"beach_crafter_about"
const ACTION_CHOOSE_SERVICE: StringName = &"choose_crafter_service"
const ACTION_EXPLAIN: StringName = &"explain_crafting"
const CHOICE_CRAFT: StringName = &"craft"
const CHOICE_ABOUT: StringName = &"about"
const CHOICE_CARDS: StringName = &"cards"
const CHOICE_LEAVE: StringName = &"leave"
const CHOICE_REQUEST: StringName = &"request"
const CHOICE_JOURNAL: StringName = &"journal"

@export var idle_animation: StringName = &"Bag_Search"
@export var talk_animation: StringName = &"Stand_Interest"
@export var interaction_prompt: String = "K : Talk"
@export var greeting_text: String = "Need something made?"
@export var craft_choice_text: String = "Craft"
@export var about_choice_text: String = "About Crafting"
@export var cards_choice_text: String = "Play Cards"
@export var leave_choice_text: String = "Leave"
@export_multiline var explanation_line_1: String = "Bring me materials from around the beach and choose a recipe."
@export_multiline var explanation_line_2: String = "The crafting screen shows what you have, what the recipe needs, and what it will make."
@export_multiline var explanation_line_3: String = "Ingredients are only consumed when a valid craft succeeds."
@export var card_opponent_id: StringName = &""
@export var card_opponent_profile: Resource

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var crafting_menu: BeachCraftingMenu = $BeachCraftingMenu
@onready var request_source: BeachCrafterRequestSource = $RequestSource

var _player_in_range: bool = false
var _crafting_service: BeachCraftingService = null
var _inventory: BeachGatheringInventory = null
var _cached_card_game: Node = null
var _dialogue_bridge: DialogueNPCBridge = null


func _ready() -> void:
	add_to_group(&"world_interaction_targets")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_play_idle()
	prompt_label.visible = false
	prompt_label.text = interaction_prompt
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	_create_dialogue_bridge()
	_configure_request_source()
	call_deferred("_bind_crafting")


func is_world_interaction_available(event: InputEvent) -> bool:
	return _player_in_range and _is_confirm(event)


func interact_from_world(event: InputEvent) -> void:
	if crafting_menu != null and crafting_menu.is_open():
		return
	if not _player_in_range:
		return
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	if not _is_confirm(event):
		return
	if _start_interaction():
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _start_interaction() -> bool:
	var craft_available := _bind_crafting()
	_play_talk()
	var card_state := _get_card_route_state()
	var choices := build_service_choices(
		craft_available,
		bool(card_state.get("configured", false)),
		bool(card_state.get("available", false)),
		craft_choice_text,
		about_choice_text,
		cards_choice_text,
		leave_choice_text
	)
	if request_source != null:
		request_source.refresh()
		choices = request_source.augment_service_choices(choices)
	if (
		_dialogue_bridge != null
		and _dialogue_bridge.start_choice_prompt(
			DIALOGUE_ID,
			ACTION_CHOOSE_SERVICE,
			&"beach_crafter",
			"Crafter",
			greeting_text,
			choices,
			PORTRAIT,
			true,
			{"source": "beach_crafter"}
		)
	):
		return true

	# If dialogue presentation is unavailable, preserve the old direct crafting
	# path rather than making a core service inaccessible.
	if craft_available:
		return _open_crafting_menu()
	_play_idle()
	return false


static func build_service_choices(
	craft_available: bool = true,
	cards_configured: bool = false,
	cards_available: bool = false,
	craft_text: String = "Craft",
	about_text: String = "About Crafting",
	cards_text: String = "Play Cards",
	leave_text: String = "Leave"
) -> Array:
	var choices: Array = [
		{
			"choice_id": CHOICE_CRAFT,
			"text": craft_text,
			"enabled": craft_available,
			"metadata": {"route": "crafting"},
		},
		{
			"choice_id": CHOICE_ABOUT,
			"text": about_text,
			"enabled": true,
			"metadata": {"route": "explanation"},
		},
	]
	if cards_configured:
		choices.append({
			"choice_id": CHOICE_CARDS,
			"text": cards_text,
			"enabled": cards_available,
			"metadata": {"route": "triple_triad"},
		})
	choices.append({
		"choice_id": CHOICE_LEAVE,
		"text": leave_text,
		"enabled": true,
		"metadata": {"route": "leave"},
	})
	return choices


func _open_crafting_menu() -> bool:
	if not _bind_crafting():
		_play_idle()
		return false
	var opened := crafting_menu.open_menu()
	if not opened:
		_play_idle()
	return opened


func _start_explanation() -> void:
	if _dialogue_bridge == null:
		_play_idle()
		return
	var lines: Array = [
		{
			"speaker_id": &"beach_crafter",
			"speaker_name": "Crafter",
			"portrait": PORTRAIT,
			"text": explanation_line_1,
		},
		{
			"speaker_id": &"beach_crafter",
			"speaker_name": "Crafter",
			"portrait": PORTRAIT,
			"text": explanation_line_2,
		},
		{
			"speaker_id": &"beach_crafter",
			"speaker_name": "Crafter",
			"portrait": PORTRAIT,
			"text": explanation_line_3,
		},
	]
	if _dialogue_bridge.start_lines(
		EXPLANATION_DIALOGUE_ID,
		ACTION_EXPLAIN,
		lines,
		true,
		{"source": "beach_crafter_help"}
	):
		return
	_play_idle()


func _create_dialogue_bridge() -> void:
	if _dialogue_bridge != null:
		return
	_dialogue_bridge = DialogueNPCBridgeScript.new() as DialogueNPCBridge
	_dialogue_bridge.name = "DialogueNPCBridge"
	add_child(_dialogue_bridge)
	_dialogue_bridge.choice_made.connect(_on_dialogue_choice_made)
	_dialogue_bridge.interaction_finished.connect(_on_dialogue_interaction_finished)


func _on_dialogue_choice_made(
	action_id: StringName,
	choice_id: StringName,
	_choice_metadata: Dictionary
) -> void:
	if action_id != ACTION_CHOOSE_SERVICE:
		return
	match choice_id:
		CHOICE_CRAFT:
			call_deferred("_open_crafting_menu")
		CHOICE_ABOUT:
			call_deferred("_start_explanation")
		CHOICE_CARDS:
			call_deferred("_open_card_game")
		CHOICE_REQUEST, CHOICE_JOURNAL:
			# BeachCrafterRequestSource listens to the same bridge signal and owns
			# request/journal routing. Keep service ownership out of this NPC.
			pass
		CHOICE_LEAVE:
			_play_idle()
		_:
			_play_idle()


func _on_dialogue_interaction_finished(
	action_id: StringName,
	reason: StringName
) -> void:
	if action_id == ACTION_CHOOSE_SERVICE:
		if reason != &"choice_selected":
			_play_idle()
		return
	if action_id != ACTION_EXPLAIN:
		return
	if reason == &"completed":
		call_deferred("_start_interaction")
		return
	_play_idle()


func _configure_request_source() -> void:
	if request_source == null or _dialogue_bridge == null:
		return
	request_source.configure(_dialogue_bridge, PORTRAIT)
	if not request_source.return_to_services_requested.is_connected(_on_request_return_to_services):
		request_source.return_to_services_requested.connect(_on_request_return_to_services)
	if not request_source.idle_requested.is_connected(_on_request_idle_requested):
		request_source.idle_requested.connect(_on_request_idle_requested)


func _on_request_return_to_services() -> void:
	if not _player_in_range:
		_play_idle()
		return
	call_deferred("_start_interaction")


func _on_request_idle_requested() -> void:
	_play_idle()


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

	var scene := GameplaySceneRoot.resolve(tree)
	if scene == null:
		return null
	var fishing := scene.find_child("Fishing", true, false)
	if fishing != null:
		var candidate = fishing.get("session_services")
		if candidate is Node:
			return candidate
	return null


func _get_card_route_state() -> Dictionary:
	var configured := (
		card_opponent_id != &""
		or card_opponent_profile != null
	)
	if not configured:
		return {"configured": false, "available": false}
	var game := _find_card_game()
	if game == null:
		return {"configured": true, "available": false}
	if (
		card_opponent_id != &""
		and game.has_method("get_opponent_availability")
	):
		var availability: Dictionary = game.call(
			"get_opponent_availability",
			card_opponent_id
		)
		return {
			"configured": true,
			"available": bool(availability.get("available", false)),
		}
	return {"configured": true, "available": true}


func _open_card_game() -> bool:
	if (
		card_opponent_id == &""
		and card_opponent_profile == null
	):
		_play_idle()
		return false

	var game: Node = _find_card_game()
	if game == null:
		_play_idle()
		return false

	if (
		card_opponent_id != &""
		and game.has_method("open_game_by_id")
	):
		game.call("open_game_by_id", card_opponent_id)
		return true

	if card_opponent_profile != null and game.has_method("open_game"):
		game.call("open_game", card_opponent_profile)
		return true

	_play_idle()
	return false


func _find_card_game() -> Node:
	if is_instance_valid(_cached_card_game):
		return _cached_card_game

	var tree := get_tree()
	if tree == null:
		return null
	var scene: Node = GameplaySceneRoot.resolve(tree)
	if scene == null:
		return null

	_cached_card_game = scene.find_child(
		"TripleTriadGame",
		true,
		false
	)
	return _cached_card_game


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
