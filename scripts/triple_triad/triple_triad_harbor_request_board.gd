extends Node3D
class_name TripleTriadHarborRequestBoard

signal request_reward_claimed(result: Dictionary)
signal request_reward_unavailable(result: Dictionary)

@export var required_opponent_id: StringName = &"beach_trader"
@export var locked_prompt: String = "Cards : Locked"
@export var objective_prompt: String = "Request : Beat Beach Trader"
@export var turn_in_prompt: String = "K : Turn In Request"
@export var complete_prompt: String = "Request : Complete"
@export var source_complete_prompt: String = "Cards : Complete"

@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var reward_adapter: Node = $QuestRewardAdapter

var _player_in_range: bool = false
var _game: Node = null
var _claim_in_progress: bool = false


func _ready() -> void:
	prompt_label.visible = false
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	call_deferred("_refresh_state")


func _input(event: InputEvent) -> void:
	if not _player_in_range or _claim_in_progress:
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return
	if not _is_confirm(event):
		return
	if not _can_turn_in():
		return

	_claim_in_progress = true
	var raw_result = reward_adapter.call("grant_reward")
	_claim_in_progress = false

	var result: Dictionary = {}
	if raw_result is Dictionary:
		result = (raw_result as Dictionary).duplicate(true)
	else:
		result = {
			"success": false,
			"reason": "invalid_quest_reward_result",
		}

	if bool(result.get("success", false)):
		request_reward_claimed.emit(result.duplicate(true))
	else:
		request_reward_unavailable.emit(result.duplicate(true))
	_refresh_state()
	get_viewport().set_input_as_handled()


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true
	_refresh_state()
	prompt_label.visible = true


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	prompt_label.visible = false


func _refresh_state() -> void:
	var game: Node = _find_game()
	if game == null:
		prompt_label.text = locked_prompt
		return

	if (
		game.has_method("is_card_game_unlocked")
		and not bool(game.call("is_card_game_unlocked"))
	):
		prompt_label.text = locked_prompt
		return

	if reward_adapter.has_method("is_claimed") and bool(
		reward_adapter.call("is_claimed")
	):
		prompt_label.text = complete_prompt
		return

	if _source_complete(game):
		prompt_label.text = source_complete_prompt
		return

	if _objective_complete(game):
		prompt_label.text = turn_in_prompt
	else:
		prompt_label.text = objective_prompt


func _can_turn_in() -> bool:
	var game: Node = _find_game()
	if game == null:
		return false
	if (
		game.has_method("is_card_game_unlocked")
		and not bool(game.call("is_card_game_unlocked"))
	):
		return false
	if reward_adapter.has_method("is_claimed") and bool(
		reward_adapter.call("is_claimed")
	):
		return false
	if _source_complete(game):
		return false
	return _objective_complete(game)


func _objective_complete(game: Node) -> bool:
	if game == null or not game.has_method("get_opponent_snapshot"):
		return false
	var raw_snapshot = game.call(
		"get_opponent_snapshot",
		required_opponent_id
	)
	if not (raw_snapshot is Dictionary):
		return false
	var snapshot: Dictionary = raw_snapshot
	return bool(snapshot.get("beaten_before", false))


func _source_complete(game: Node) -> bool:
	if game == null or not game.has_method("get_source_completion_snapshot"):
		return false
	var source_id: String = str(reward_adapter.get("source_id"))
	for raw_source in game.call("get_source_completion_snapshot"):
		if not (raw_source is Dictionary):
			continue
		var source: Dictionary = raw_source
		if (
			str(source.get("source_type", "")) == "quest_reward"
			and str(source.get("source_id", "")) == source_id
		):
			return bool(source.get("complete", false))
	return false


func _find_game() -> Node:
	if is_instance_valid(_game):
		return _game
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return null
	_game = tree.current_scene.find_child("TripleTriadGame", true, false)
	if _game != null and _game.has_signal("backend_state_changed"):
		var callback := Callable(self, "_on_backend_state_changed")
		if not _game.is_connected("backend_state_changed", callback):
			_game.connect("backend_state_changed", callback)
	return _game


func _on_backend_state_changed(_reason: String) -> void:
	if _player_in_range:
		_refresh_state()


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
