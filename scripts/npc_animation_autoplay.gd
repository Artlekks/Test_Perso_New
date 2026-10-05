extends Node
class_name NPCAnimationAutoplay

## Starts multi-frame NPC AnimatedSprite2D/3D animations that were assigned in
## the editor but never explicitly played at runtime.
##
## The helper only scans direct children of World (and their descendants), so it
## never touches the player, HUD, fish shadows, lure, or other fishing runtime
## sprites. NPC scripts that already started their own animation are left alone.

@export var world_path: NodePath = NodePath("../World")
@export_range(0, 8, 1) var startup_delay_frames: int = 2

var _world: Node = null


func _ready() -> void:
	for _frame in range(startup_delay_frames):
		await get_tree().process_frame
	_world = get_node_or_null(world_path)
	if _world == null:
		return
	_start_world_npc_animations()
	if not _world.child_entered_tree.is_connected(_on_world_child_entered_tree):
		_world.child_entered_tree.connect(_on_world_child_entered_tree)


func _on_world_child_entered_tree(node: Node) -> void:
	call_deferred("_start_animation_tree", node)


func _start_world_npc_animations() -> void:
	for child in _world.get_children():
		if _is_environment_child(child):
			continue
		_start_animation_tree(child)


func _is_environment_child(node: Node) -> bool:
	var node_name := str(node.name)
	return node_name in [
		"WorldEnvironment",
		"DirectionalLight3D",
		"FishZone_V2",
		"beach",
		"DepthFloor",
		"ShoreBlocker",
	]


func _start_animation_tree(node: Node) -> void:
	if node == null:
		return

	if node is AnimatedSprite3D:
		_start_sprite_3d(node as AnimatedSprite3D)
	elif node is AnimatedSprite2D:
		_start_sprite_2d(node as AnimatedSprite2D)

	for child in node.get_children():
		_start_animation_tree(child)


func _start_sprite_3d(sprite: AnimatedSprite3D) -> void:
	if sprite == null or sprite.sprite_frames == null or sprite.is_playing():
		return
	var animation_name := _choose_animation(sprite.sprite_frames, sprite.animation)
	if animation_name == &"":
		return
	if is_zero_approx(sprite.speed_scale):
		sprite.speed_scale = 1.0
	sprite.animation = animation_name
	sprite.play(animation_name)


func _start_sprite_2d(sprite: AnimatedSprite2D) -> void:
	if sprite == null or sprite.sprite_frames == null or sprite.is_playing():
		return
	var animation_name := _choose_animation(sprite.sprite_frames, sprite.animation)
	if animation_name == &"":
		return
	if is_zero_approx(sprite.speed_scale):
		sprite.speed_scale = 1.0
	sprite.animation = animation_name
	sprite.play(animation_name)


func _choose_animation(frames: SpriteFrames, current: StringName) -> StringName:
	if frames == null:
		return &""

	if frames.has_animation(current) and frames.get_frame_count(current) > 1:
		return current

	var names := frames.get_animation_names()
	var preferred_tokens := PackedStringArray([
		"idle",
		"stand",
		"sit",
		"rest",
		"breathe",
		"smoke",
	])
	for token in preferred_tokens:
		for raw_name in names:
			var candidate := StringName(raw_name)
			if (
				str(candidate).to_lower().contains(token)
				and frames.get_frame_count(candidate) > 1
			):
				return candidate

	for raw_name in names:
		var candidate := StringName(raw_name)
		if (
			frames.get_frame_count(candidate) > 1
			and frames.get_animation_loop(candidate)
		):
			return candidate

	for raw_name in names:
		var candidate := StringName(raw_name)
		if frames.get_frame_count(candidate) > 1:
			return candidate

	return &""
