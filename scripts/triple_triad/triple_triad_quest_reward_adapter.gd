extends Node
class_name TripleTriadQuestRewardAdapter
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")

signal reward_granted(result: Dictionary)
signal reward_failed(result: Dictionary)

@export var source_id: StringName = &"town_requests"
@export var quest_event_id: StringName = &""
@export var source_context: StringName = &"quest"

var _game: Node = null


func grant_reward(
	override_event_id: StringName = &"",
	override_context: StringName = &""
) -> Dictionary:
	var game: Node = _find_game()
	if game == null or not game.has_method("claim_quest_card_reward"):
		var missing := {
			"success": false,
			"reason": "triple_triad_game_unavailable",
		}
		reward_failed.emit(missing.duplicate(true))
		return missing
	if not _backend_ready(game):
		var not_ready := {
			"success": false,
			"reason": "triple_triad_backend_not_ready",
		}
		reward_failed.emit(not_ready.duplicate(true))
		return not_ready

	var resolved_event_id: StringName = _resolved_event_id()
	if not String(override_event_id).is_empty():
		resolved_event_id = override_event_id
	var resolved_context: StringName = source_context
	if not String(override_context).is_empty():
		resolved_context = override_context

	var raw_result = game.call(
		"claim_quest_card_reward",
		source_id,
		resolved_event_id,
		resolved_context
	)
	if not (raw_result is Dictionary):
		var invalid := {
			"success": false,
			"reason": "invalid_quest_reward_result",
		}
		reward_failed.emit(invalid.duplicate(true))
		return invalid

	var result: Dictionary = (raw_result as Dictionary).duplicate(true)
	if bool(result.get("success", false)):
		reward_granted.emit(result.duplicate(true))
	else:
		reward_failed.emit(result.duplicate(true))
	return result


func is_claimed(override_event_id: StringName = &"") -> bool:
	var game: Node = _find_game()
	if game == null or not game.has_method("has_world_reward_event_claimed"):
		return false
	if not _backend_ready(game):
		return false
	var resolved_event_id: StringName = _resolved_event_id()
	if not String(override_event_id).is_empty():
		resolved_event_id = override_event_id
	return bool(
		game.call(
			"has_world_reward_event_claimed",
			resolved_event_id
		)
	)


func _backend_ready(game: Node) -> bool:
	if game == null:
		return false
	# TripleTriadGame is composed in stages. Any adapter operation that reaches
	# the world gateway must respect the facade's explicit readiness contract.
	if game.has_method("is_backend_ready"):
		return bool(game.call("is_backend_ready"))
	# Compatibility for older game facades that predate the readiness method.
	return true


func _resolved_event_id() -> StringName:
	if not String(quest_event_id).is_empty():
		return quest_event_id
	return StringName(
		"quest:%s:%s"
		% [String(source_id), str(get_path())]
	)


func _find_game() -> Node:
	if is_instance_valid(_game):
		return _game
	var tree: SceneTree = get_tree()
	if tree == null or GameplaySceneRoot.resolve(tree) == null:
		return null
	_game = GameplaySceneRoot.resolve(tree).find_child("TripleTriadGame", true, false)
	return _game
