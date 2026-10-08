extends Node
class_name WorldInteractionRouter

## Scene-local input owner. Actors expose eligibility and retain their own
## dialogue/service behavior; they never compete in SceneTree input traversal.
const TARGET_GROUP: StringName = &"world_interaction_targets"

var _player: Node3D = null
var _game_mode: Node = null
var _claimed_keys: Dictionary = {}


func configure(player: Node3D, game_mode: Node) -> void:
	_player = player
	_game_mode = game_mode
	_claimed_keys.clear()


func _ready() -> void:
	# Observe releases during modal pauses, but never dispatch paused input.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	handle_event(event)


func handle_event(event: InputEvent) -> bool:
	var card_action := event.is_action(&"world_card_challenge")
	if not (event is InputEventKey) and not card_action:
		return false
	var key_event := event as InputEventKey
	var key: int = KEY_C if card_action else key_event.physical_keycode
	if key == 0:
		key = key_event.keycode
	if not event.is_pressed():
		_claimed_keys.erase(key)
		return false
	var tree := get_tree()
	if tree == null or not is_instance_valid(_player) or _player.is_queued_for_deletion():
		return false
	if not is_instance_valid(_game_mode) or not _game_mode.has_method("is_exploration"):
		return false
	if _game_mode.is_queued_for_deletion() or not _game_mode.is_exploration():
		# Fishing owns K throughout its entire mode, including animations.
		return false
	if _claimed_keys.has(key):
		get_viewport().set_input_as_handled()
		return true
	if tree.paused or event.is_echo():
		return false
	if not card_action and key_event.keycode not in [KEY_K, KEY_ENTER] and key_event.physical_keycode not in [KEY_K, KEY_ENTER]:
		return false
	var target := select_target(
		_player, tree.get_nodes_in_group(TARGET_GROUP), event
	)
	if target == null:
		return false
	_claimed_keys[key] = true
	# Consume before calling an actor: opening dialogue/menus changes state
	# synchronously, and must not retarget this same physical press.
	get_viewport().set_input_as_handled()
	target.call("interact_from_world", event)
	return true


static func facing_allows(forward: Vector3, displacement: Vector3) -> bool:
	var facing := Vector2(forward.x, forward.z)
	var toward := Vector2(displacement.x, displacement.z)
	if facing.length_squared() < 0.000001 or toward.length_squared() < 0.000001:
		return false
	var step := PI / 4.0
	var facing_sector := int(round(atan2(facing.x, facing.y) / step))
	var target_sector := int(round(atan2(toward.x, toward.y) / step))
	var difference := posmod(target_sector - facing_sector, 8)
	return difference == 0 or difference == 1 or difference == 7


static func select_target(player: Node3D, candidates: Array, event: InputEvent) -> Node3D:
	if not is_instance_valid(player) or player.is_queued_for_deletion():
		return null
	var best: Node3D = null
	var best_distance: float = INF
	var best_alignment: float = -INF
	var forward := player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	for candidate in candidates:
		if not is_instance_valid(candidate) or not (candidate is Node3D):
			continue
		var target := candidate as Node3D
		if target.is_queued_for_deletion() or not target.is_inside_tree():
			continue
		if not target.has_method("is_world_interaction_available") or not target.has_method("interact_from_world"):
			continue
		if not bool(target.call("is_world_interaction_available", event)):
			continue
		var displacement := target.global_position - player.global_position
		displacement.y = 0.0
		if not facing_allows(forward, displacement):
			continue
		var distance := displacement.length_squared()
		var alignment := forward.dot(displacement.normalized())
		# Nearest, then most centered, then stable scene path; group traversal
		# and sibling insertion order do not determine the winner.
		if best == null or distance < best_distance or (
			distance == best_distance and (alignment > best_alignment or (
				alignment == best_alignment and String(target.get_path()) < String(best.get_path())
			))
		):
			best = target
			best_distance = distance
			best_alignment = alignment
	return best
