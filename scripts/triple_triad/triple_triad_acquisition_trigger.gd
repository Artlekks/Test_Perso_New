extends Node
class_name TripleTriadAcquisitionTrigger

signal claim_completed(result: Dictionary)

@export var bundle_id: StringName = &"salvaged_card_case"
@export var source_context: StringName = &"world_trigger"

var _cached_game: Node = null


## Generic bridge for fishing salvage, treasure, quests, shops, or scripted
## events. External gameplay code calls trigger(); this node does not know how
## the source event was produced.
func trigger() -> Dictionary:
	var game: Node = _find_game()
	if game == null or not game.has_method("claim_acquisition_bundle"):
		var failed := {
			"success": false,
			"reason": "triple_triad_game_unavailable",
			"bundle_id": String(bundle_id),
		}
		claim_completed.emit(failed.duplicate(true))
		return failed
	var result: Dictionary = game.call(
		"claim_acquisition_bundle",
		bundle_id,
		source_context
	)
	claim_completed.emit(result.duplicate(true))
	return result


func _find_game() -> Node:
	if is_instance_valid(_cached_game):
		return _cached_game
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return null
	_cached_game = tree.current_scene.find_child("TripleTriadGame", true, false)
	return _cached_game
