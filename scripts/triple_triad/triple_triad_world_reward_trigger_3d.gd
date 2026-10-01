extends Node3D
class_name TripleTriadWorldRewardTrigger3D

signal reward_claimed(result: Dictionary)
signal reward_unavailable(result: Dictionary)

@export_enum("treasure_cache", "quest_reward", "tournament_reward")
var source_type_text: String = "treasure_cache"
@export var source_id: StringName = &"harbor_lockbox"
@export var event_id: StringName = &""
@export var one_shot: bool = true
@export var interaction_prompt: String = "K : Search Cards"
@export var collected_prompt: String = "Cards : Collected"
@export var complete_prompt: String = "Cards : Complete"
@export var locked_prompt: String = "Cards : Locked"

@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea

var _player_in_range: bool = false
var _game: Node = null
var _disabled: bool = false


func _ready() -> void:
	prompt_label.visible = false
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	call_deferred("_refresh_state")


func claim() -> Dictionary:
	if _disabled:
		return {"success": false, "reason": "trigger_disabled"}

	var game: Node = _find_game()
	if game == null or not game.has_method("claim_world_source_reward"):
		var missing := {
			"success": false,
			"reason": "triple_triad_game_unavailable",
		}
		reward_unavailable.emit(missing.duplicate(true))
		return missing

	var raw_result = game.call(
		"claim_world_source_reward",
		StringName(source_type_text),
		source_id,
		StringName("world3d:%s" % str(get_path())),
		_resolved_event_id(),
		one_shot
	)
	if not (raw_result is Dictionary):
		var invalid := {
			"success": false,
			"reason": "invalid_world_reward_result",
		}
		reward_unavailable.emit(invalid.duplicate(true))
		return invalid

	var result: Dictionary = (raw_result as Dictionary).duplicate(true)
	if bool(result.get("success", false)):
		reward_claimed.emit(result.duplicate(true))
		if one_shot:
			_disabled = true
	else:
		reward_unavailable.emit(result.duplicate(true))
	_refresh_state()
	return result


func _input(event: InputEvent) -> void:
	if not _player_in_range or _disabled:
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return
	if not _is_confirm(event):
		return
	claim()
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
		one_shot
		and game.has_method("has_world_reward_event_claimed")
		and bool(
			game.call(
				"has_world_reward_event_claimed",
				_resolved_event_id()
			)
		)
	):
		_disabled = true
		prompt_label.text = collected_prompt
		return

	var source_progress: Dictionary = _source_progress(game)
	if not source_progress.is_empty():
		if bool(source_progress.get("complete", false)):
			prompt_label.text = complete_prompt
			return
		if not bool(source_progress.get("rank_available", true)):
			prompt_label.text = locked_prompt
			return
	prompt_label.text = interaction_prompt


func _source_progress(game: Node) -> Dictionary:
	if not game.has_method("get_source_completion_snapshot"):
		return {}
	for raw_source in game.call("get_source_completion_snapshot"):
		if not (raw_source is Dictionary):
			continue
		var source: Dictionary = raw_source
		if (
			str(source.get("source_type", "")) == source_type_text
			and str(source.get("source_id", "")) == String(source_id)
		):
			return source.duplicate(true)
	return {}


func _find_game() -> Node:
	if is_instance_valid(_game):
		return _game
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


func _resolved_event_id() -> StringName:
	if not String(event_id).is_empty():
		return event_id
	return StringName(
		"%s:%s:%s"
		% [source_type_text, String(source_id), str(get_path())]
	)


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
