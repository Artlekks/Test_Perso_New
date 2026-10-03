extends Node3D

@export var interaction_prompt: String = "C : Cards"
@export var locked_prompt: String = "Cards : Locked"
@export var rematch_prompt: String = "C : Rematch"
@export var veteran_rematch_prompt: String = "C : Veteran Rematch"
## Stable registry key. New NPC instances should use this.
@export var opponent_id: StringName = &""
## Legacy/fallback direct profile reference for older scenes.
@export var opponent_profile: Resource

@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea

const CARD_CHALLENGE_INTRO_COUNTER_ID: StringName = &"tutorial:card_challenge_intro"
const CARD_CHALLENGE_INTRO_TEXT := (
	"Got cards? Want a game?\n"
	+ "Press C near card players to challenge them."
)

var _player_in_range: bool = false
var _cached_game: Node = null
var _signal_bound_game: Node = null
var _intro_tween: Tween = null


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

		if _should_show_card_challenge_intro(game):
			_mark_card_challenge_intro_seen(game)
			_show_card_challenge_intro()
			get_viewport().set_input_as_handled()
			return

		if (
			opponent_id != &""
			and game.has_method("open_game_by_id")
		):
			game.call("open_game_by_id", opponent_id)
		elif game.has_method("open_game"):
			game.call("open_game", opponent_profile)
	get_viewport().set_input_as_handled()


func _find_game() -> Node:
	if is_instance_valid(_cached_game):
		_bind_game_signals(_cached_game)
		return _cached_game
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return null
	_cached_game = tree.current_scene.find_child("TripleTriadGame", true, false)
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


func _should_show_card_challenge_intro(game: Node) -> bool:
	if game == null:
		return false

	# Existing saves that have already completed a match should never receive a
	# retroactive onboarding interruption just because this counter is new.
	if game.has_method("get_player_snapshot"):
		var raw_player = game.call("get_player_snapshot")
		if raw_player is Dictionary:
			if int((raw_player as Dictionary).get("matches", 0)) > 0:
				return false

	if not game.has_method("get_world_reward_delivery_snapshot"):
		return true
	var raw_delivery = game.call("get_world_reward_delivery_snapshot")
	if not (raw_delivery is Dictionary):
		return true
	var raw_counters = (raw_delivery as Dictionary).get("counters", {})
	if not (raw_counters is Dictionary):
		return true
	return int(
		(raw_counters as Dictionary).get(
			String(CARD_CHALLENGE_INTRO_COUNTER_ID),
			0
		)
	) <= 0


func _mark_card_challenge_intro_seen(game: Node) -> void:
	if game == null or not game.has_method("advance_world_reward_counter"):
		return
	game.call(
		"advance_world_reward_counter",
		CARD_CHALLENGE_INTRO_COUNTER_ID
	)


func _show_card_challenge_intro() -> void:
	if not is_instance_valid(prompt_label):
		return
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	prompt_label.text = CARD_CHALLENGE_INTRO_TEXT
	prompt_label.visible = true
	_intro_tween = create_tween()
	_intro_tween.tween_interval(4.5)
	_intro_tween.tween_callback(_finish_card_challenge_intro)


func _finish_card_challenge_intro() -> void:
	_intro_tween = null
	if not is_instance_valid(prompt_label):
		return
	prompt_label.visible = false
	_refresh_prompt_text()


func _is_player_body(body: Node) -> bool:
	return body != null and body is CharacterBody3D and body.name == "CharacterBody3D"


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
