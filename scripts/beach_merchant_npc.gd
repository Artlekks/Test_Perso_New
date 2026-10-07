extends Node3D

const DialogueNPCBridgeScript = preload("res://scripts/dialogue/dialogue_npc_bridge.gd")
const EconomyContextScript = preload("res://scripts/economy/merchant_economy_context.gd")
const PORTRAIT: Texture2D = preload("res://data/dialogue/portraits/beach_merchant.tres")

const DIALOGUE_ID: StringName = &"beach_merchant_services"
const ACTION_CHOOSE_SERVICE: StringName = &"choose_service"
const CHOICE_BUY: StringName = &"buy"
const CHOICE_SELL: StringName = &"sell"
const CHOICE_CARDS: StringName = &"cards"
const CHOICE_LEAVE: StringName = &"leave"

@export var idle_animation: StringName = &"Bag_Search"
@export var talk_animation: StringName = &"Stand_Interest"
@export var interaction_prompt: String = "K : Talk"
@export var greeting_text: String = "Take a look."
@export var buy_choice_text: String = "Buy"
@export var sell_choice_text: String = "Sell"
@export var cards_choice_text: String = "Play Cards"
@export var leave_choice_text: String = "Leave"

@export_category("Economy Access")
@export var economy_context: EconomyContextScript
## Optional mixed-role support. The current beach merchant does not use these;
## the separate TripleTriadOpponentNPC owns the beach_trader duel.
@export var card_opponent_id: StringName = &""
@export var card_opponent_profile: Resource

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea

var _player_in_range: bool = false
var _cached_menu: Node = null
var _cached_card_game: Node = null
var _dialogue_bridge: DialogueNPCBridge = null


func _ready() -> void:
	add_to_group(&"world_economy_sources")
	add_to_group(&"world_interaction_targets")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_play_idle()
	prompt_label.visible = false
	prompt_label.text = interaction_prompt
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	_create_dialogue_bridge()


func is_world_interaction_available(event: InputEvent) -> bool:
	return _player_in_range and _is_confirm(event)


func interact_from_world(event: InputEvent) -> void:
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
	var menu_available := _find_economy_menu() != null
	var card_state := _get_card_route_state()
	var choices := build_service_choices(
		menu_available,
		menu_available,
		bool(card_state.get("configured", false)),
		bool(card_state.get("available", false)),
		buy_choice_text,
		sell_choice_text,
		cards_choice_text,
		leave_choice_text
	)
	if (
		_dialogue_bridge != null
		and _dialogue_bridge.start_choice_prompt(
			DIALOGUE_ID,
			ACTION_CHOOSE_SERVICE,
			&"beach_merchant",
			"Merchant",
			greeting_text,
			choices,
			PORTRAIT,
			true,
			{"source": "beach_merchant"}
		)
	):
		return

	# Presentation failure must never strand a core economy interaction.
	_open_buy_menu()


static func build_service_choices(
	buy_available: bool = true,
	sell_available: bool = true,
	cards_configured: bool = false,
	cards_available: bool = false,
	buy_text: String = "Buy",
	sell_text: String = "Sell",
	cards_text: String = "Play Cards",
	leave_text: String = "Leave"
) -> Array:
	var choices: Array = [
		{
			"choice_id": CHOICE_BUY,
			"text": buy_text,
			"enabled": buy_available,
			"metadata": {"route": "economy_buy"},
		},
		{
			"choice_id": CHOICE_SELL,
			"text": sell_text,
			"enabled": sell_available,
			"metadata": {"route": "economy_sell"},
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
		CHOICE_BUY:
			call_deferred("_open_buy_menu")
		CHOICE_SELL:
			call_deferred("_open_sell_menu")
		CHOICE_CARDS:
			_clear_economy_access_context()
			call_deferred("_open_card_game")
		CHOICE_LEAVE:
			_clear_economy_access_context()
			_play_idle()
		_:
			_play_idle()


func _on_dialogue_interaction_finished(
	action_id: StringName,
	reason: StringName
) -> void:
	if action_id != ACTION_CHOOSE_SERVICE:
		return
	# A valid selection is already routed by choice_made. Cancellation or any
	# abnormal finish simply restores the NPC's idle presentation.
	if reason != &"choice_selected":
		_clear_economy_access_context()
		_play_idle()


func _open_buy_menu() -> void:
	_open_economy_menu(0)


func _open_sell_menu() -> void:
	_open_economy_menu(1)


func _open_economy_menu(mode: int) -> void:
	# A deferred dialogue choice must not reopen a merchant already left.
	if not _player_in_range or is_queued_for_deletion():
		return
	var target_menu := _find_economy_menu()
	if target_menu == null or economy_context == null:
		_play_idle()
		return
	if not bool(target_menu.call("open_merchant_menu", economy_context, self, mode)):
		_play_idle()


func _open_card_game() -> void:
	var game := _find_card_game()
	if game == null:
		_play_idle()
		return
	if card_opponent_id != &"" and game.has_method("open_game_by_id"):
		game.call("open_game_by_id", card_opponent_id)
		return
	if card_opponent_profile != null and game.has_method("open_game"):
		game.call("open_game", card_opponent_profile)
		return
	_play_idle()


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


func _clear_economy_access_context() -> void:
	# Only this merchant's active menu may be closed. Nearby NPC callbacks
	# must never clear another merchant's or debug tool's access context.
	if is_instance_valid(_cached_menu):
		_cached_menu.call("close_for_merchant", self)


func _exit_tree() -> void:
	_clear_economy_access_context()


func _find_economy_menu() -> Node:
	if is_instance_valid(_cached_menu):
		_bind_menu_signals(_cached_menu)
		return _cached_menu
	var scene := get_tree().current_scene
	if scene == null:
		return null
	_cached_menu = scene.find_child("FishingEconomyMenu", true, false)
	_bind_menu_signals(_cached_menu)
	return _cached_menu


func _bind_menu_signals(menu: Node) -> void:
	if menu == null or not menu.has_signal("closed"):
		return
	var callback := Callable(self, "_on_economy_menu_closed")
	if not menu.is_connected("closed", callback):
		menu.connect("closed", callback)


func _on_economy_menu_closed() -> void:
	_clear_economy_access_context()
	_play_idle()


func _find_card_game() -> Node:
	if is_instance_valid(_cached_card_game):
		_bind_card_game_signals(_cached_card_game)
		return _cached_card_game
	var scene := get_tree().current_scene
	if scene == null:
		return null
	_cached_card_game = scene.find_child("TripleTriadGame", true, false)
	_bind_card_game_signals(_cached_card_game)
	return _cached_card_game


func _bind_card_game_signals(game: Node) -> void:
	if game == null or not game.has_signal("closed"):
		return
	var callback := Callable(self, "_on_card_game_closed")
	if not game.is_connected("closed", callback):
		game.connect("closed", callback)


func _on_card_game_closed() -> void:
	_play_idle()


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
	_clear_economy_access_context()
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
