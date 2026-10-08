extends Node3D
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")

const DialogueNPCBridgeScript = preload("res://scripts/dialogue/dialogue_npc_bridge.gd")
const NPCDialogueRouterScript = preload("res://scripts/dialogue/npc_dialogue_router.gd")
const ACTION_OPEN_CARDS: StringName = &"open_cards"

@export var interaction_prompt: String = "C : Cards"
@export var locked_prompt: String = "Cards : Locked"
@export var rematch_prompt: String = "C : Rematch"
@export var veteran_rematch_prompt: String = "C : Veteran Rematch"
## Stable registry key. New NPC instances should use this.
@export var opponent_id: StringName = &""
## Legacy/fallback direct profile reference for older scenes.
@export var opponent_profile: Resource

@onready var animated_sprite: AnimatedSprite3D = $GroundPresentation/VisualAnchor/AnimatedSprite3D
@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea

var _player_in_range: bool = false
var _cached_game: Node = null
var _signal_bound_game: Node = null
var _dialogue_bridge: Node = null
var _pending_game: Node = null


func _ready() -> void:
	add_to_group(&"world_interaction_targets")
	prompt_label.visible = false
	prompt_label.text = interaction_prompt
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	_create_dialogue_bridge()


func is_world_interaction_available(event: InputEvent) -> bool:
	return _player_in_range and _is_card_action(event)


func interact_from_world(event: InputEvent) -> void:
	if not _player_in_range:
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return
	if not _is_card_action(event):
		return
	var game: Node = _find_game()
	if game != null:
		if opponent_id != &"" and game.has_method("get_opponent_availability"):
			var availability: Dictionary = game.call(
				"get_opponent_availability",
				opponent_id
			)
			if not bool(availability.get("available", false)):
				_refresh_prompt_text()
				get_viewport().set_input_as_handled()
				return
		if not _start_card_conversation(game):
			_open_card_game(game)
	get_viewport().set_input_as_handled()


func _start_card_conversation(game: Node) -> bool:
	var bridge := _ensure_dialogue_bridge()
	if bridge == null:
		return false
	var speaker_name := _get_opponent_display_name()
	var greeting := _get_card_greeting(game)
	_pending_game = game
	var started: bool = NPCDialogueRouterScript.start_spoken_line(
		bridge,
		StringName("triple_triad_talk_%s" % str(opponent_id)),
		ACTION_OPEN_CARDS,
		opponent_id,
		speaker_name,
		greeting,
		animated_sprite,
		true,
		{"source": "triple_triad_opponent"}
	)
	if not started:
		_pending_game = null
	return started


func _get_opponent_display_name() -> String:
	if opponent_profile != null:
		var raw_name = opponent_profile.get("display_name")
		if raw_name != null:
			var clean_name := str(raw_name).strip_edges()
			if not clean_name.is_empty():
				return clean_name
	return NPCDialogueRouterScript.humanize_id(
		opponent_id,
		"",
		"Card Player"
	)


func _get_card_greeting(game: Node) -> String:
	var stage := 0
	if (
		opponent_id != &""
		and game != null
		and game.has_method("get_opponent_evolution_snapshot")
	):
		var evolution: Dictionary = game.call(
			"get_opponent_evolution_snapshot",
			opponent_id
		)
		stage = int(evolution.get("stage", 0))
	if stage >= 3:
		return "Another game. Show me what you've learned."
	if stage > 0:
		return "Back for another round?"
	return "Care for a game of cards?"


func _create_dialogue_bridge() -> void:
	if is_instance_valid(_dialogue_bridge):
		return
	_dialogue_bridge = DialogueNPCBridgeScript.new()
	_dialogue_bridge.name = "DialogueNPCBridge"
	add_child(_dialogue_bridge)
	_dialogue_bridge.interaction_finished.connect(
		_on_dialogue_interaction_finished
	)


func _ensure_dialogue_bridge() -> Node:
	if not is_instance_valid(_dialogue_bridge):
		_create_dialogue_bridge()
	return _dialogue_bridge


func _on_dialogue_interaction_finished(
	action_id: StringName,
	reason: StringName
) -> void:
	if action_id != ACTION_OPEN_CARDS:
		return
	var game := _pending_game
	_pending_game = null
	if reason != &"completed":
		return
	if is_instance_valid(game):
		call_deferred("_open_card_game", game)


func _open_card_game(game: Node) -> void:
	if game == null:
		return
	if (
		opponent_id != &""
		and game.has_method("open_game_by_id")
	):
		game.call("open_game_by_id", opponent_id)
		return
	if game.has_method("open_game"):
		game.call("open_game", opponent_profile)


func _find_game() -> Node:
	if is_instance_valid(_cached_game):
		_bind_game_signals(_cached_game)
		return _cached_game
	var scene: Node = GameplaySceneRoot.resolve(get_tree())
	if scene == null:
		return null
	_cached_game = scene.find_child("TripleTriadGame", true, false)
	_bind_game_signals(_cached_game)
	return _cached_game


func _bind_game_signals(game: Node) -> void:
	if game == null or _signal_bound_game == game:
		return

	_signal_bound_game = game

	var unlock_callback := Callable(
		self,
		"_on_card_game_unlock_changed"
	)
	if (
		game.has_signal("card_game_unlock_changed")
		and not game.is_connected(
			"card_game_unlock_changed",
			unlock_callback
		)
	):
		game.connect(
			"card_game_unlock_changed",
			unlock_callback
		)

	var state_callback := Callable(
		self,
		"_on_backend_state_changed"
	)
	if (
		game.has_signal("backend_state_changed")
		and not game.is_connected(
			"backend_state_changed",
			state_callback
		)
	):
		game.connect(
			"backend_state_changed",
			state_callback
		)

	var closed_callback := Callable(
		self,
		"_on_card_game_closed"
	)
	if (
		game.has_signal("closed")
		and not game.is_connected(
			"closed",
			closed_callback
		)
	):
		game.connect(
			"closed",
			closed_callback
		)


func _on_card_game_unlock_changed(_unlocked: bool) -> void:
	if _player_in_range:
		_refresh_prompt_text()


func _on_card_game_closed() -> void:
	if _player_in_range:
		_refresh_prompt_text()


func _on_backend_state_changed(_reason: String) -> void:
	if _player_in_range:
		_refresh_prompt_text()


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true
	_refresh_prompt_text()
	prompt_label.visible = false


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	prompt_label.visible = false


func _refresh_prompt_text() -> void:
	prompt_label.text = interaction_prompt
	if opponent_id == &"":
		return
	var game: Node = _find_game()
	if game == null or not game.has_method("get_opponent_availability"):
		return
	var availability: Dictionary = game.call(
		"get_opponent_availability",
		opponent_id
	)
	if not bool(availability.get("available", false)):
		prompt_label.text = locked_prompt
		return

	if game.has_method("get_opponent_evolution_snapshot"):
		var evolution: Dictionary = game.call(
			"get_opponent_evolution_snapshot",
			opponent_id
		)
		var stage: int = int(evolution.get("stage", 0))
		if stage >= 3:
			prompt_label.text = veteran_rematch_prompt
		elif stage > 0:
			prompt_label.text = rematch_prompt


func _is_player_body(body: Node) -> bool:
	return body != null and body is CharacterBody3D and body.name == "CharacterBody3D"


func _is_card_action(event: InputEvent) -> bool:
	return event.is_action_pressed(&"world_card_challenge", false)
