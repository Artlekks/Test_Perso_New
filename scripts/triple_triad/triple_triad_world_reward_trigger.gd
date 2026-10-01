extends Area2D
class_name TripleTriadWorldRewardTrigger

signal reward_claimed(result: Dictionary)
signal reward_unavailable(result: Dictionary)

@export_enum("treasure_cache", "quest_reward", "tournament_reward")
var source_type_text: String = "treasure_cache"
@export var source_id: StringName = &"harbor_lockbox"
@export var event_id: StringName = &""
@export var one_shot: bool = true
@export var interaction_key: Key = KEY_K
@export var disable_after_success: bool = true

var _body_count: int = 0
var _disabled: bool = false
var _game: Node = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_process_unhandled_input(true)
	call_deferred("_refresh_claim_state")


func claim() -> Dictionary:
	if _disabled:
		return {
			"success": false,
			"reason": "trigger_disabled",
		}

	var game: Node = _find_game()
	if game == null or not game.has_method("claim_world_source_reward"):
		var missing_result := {
			"success": false,
			"reason": "triple_triad_game_unavailable",
		}
		reward_unavailable.emit(missing_result.duplicate(true))
		return missing_result

	var resolved_event_id: StringName = _resolved_event_id()
	var context := StringName(
		"world_trigger:%s" % str(get_path())
	)
	var raw_result = game.call(
		"claim_world_source_reward",
		StringName(source_type_text),
		source_id,
		context,
		resolved_event_id,
		one_shot
	)
	if not (raw_result is Dictionary):
		var invalid_result := {
			"success": false,
			"reason": "invalid_world_reward_result",
		}
		reward_unavailable.emit(invalid_result.duplicate(true))
		return invalid_result

	var result: Dictionary = (raw_result as Dictionary).duplicate(true)
	if bool(result.get("success", false)):
		reward_claimed.emit(result.duplicate(true))
		if one_shot and disable_after_success:
			_disable_trigger()
	else:
		reward_unavailable.emit(result.duplicate(true))
		if (
			one_shot
			and str(result.get("reason", "")) == "event_already_claimed"
		):
			_disable_trigger()
	return result


func _unhandled_input(event: InputEvent) -> void:
	if _disabled or _body_count <= 0:
		return
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != interaction_key:
		return
	claim()
	get_viewport().set_input_as_handled()


func _on_body_entered(_body: Node) -> void:
	_body_count += 1


func _on_body_exited(_body: Node) -> void:
	_body_count = maxi(0, _body_count - 1)


func _find_game() -> Node:
	if is_instance_valid(_game):
		return _game
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return null
	_game = tree.current_scene.find_child(
		"TripleTriadGame",
		true,
		false
	)
	return _game


func _resolved_event_id() -> StringName:
	if not String(event_id).is_empty():
		return event_id
	return StringName(
		"%s:%s:%s"
		% [
			source_type_text,
			String(source_id),
			str(get_path()),
		]
	)


func _refresh_claim_state() -> void:
	if not one_shot:
		return
	var game: Node = _find_game()
	if game == null or not game.has_method("has_world_reward_event_claimed"):
		return
	if bool(game.call("has_world_reward_event_claimed", _resolved_event_id())):
		_disable_trigger()


func _disable_trigger() -> void:
	_disabled = true
	monitoring = false
	monitorable = false
	set_process_unhandled_input(false)
