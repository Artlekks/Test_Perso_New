@tool
extends Node3D
class_name GroundPresentation
const ViewDirection = preload("res://scripts/world/view_relative_direction.gd")
## A root-relative physical feet anchor, shared across all grounded sheets.
## Sprite frame padding changes pixel alignment, never the world feet point.
@export var profile: WorldActorPresentationProfile
@onready var visual_anchor: Node3D = $VisualAnchor
@onready var shadow: WorldBlobShadow = $ShadowAnchor/WorldBlobShadow
var sprite: SpriteBase3D
var directional_pose: String = ""
var world_facing: Vector3 = Vector3.BACK
var _applied_pose: String = ""
var _directions: Dictionary = {}
var _last_flip_h := false
var _explicit_world_facing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 240
	# Inherit translation immediately; a top-level visual would lag physics by
	# one presentation update. Only the shadow opts out of actor orientation.
	top_level = false
	for child in visual_anchor.get_children():
		if child is SpriteBase3D and not child is Label3D: sprite = child
	if sprite is AnimatedSprite3D:
		sprite.frame_changed.connect(apply_frame)
		sprite.animation_changed.connect(apply_frame)
	apply_profile()
	update_anchor()
	if not Engine.is_editor_hint(): _install_marker_anchor.call_deferred()

func _install_marker_anchor() -> void:
	var actor := get_parent() as Node3D
	if actor == null or profile == null or actor.has_node("WorldMarkerAnchor"): return
	if not actor.has_node("PromptLabel3D") and not actor.has_node("RequestMarker"): return
	var anchor := WorldMarkerAnchor.new()
	anchor.name = "WorldMarkerAnchor"
	actor.add_child(anchor)
	anchor.configure(actor, profile)

func _process(_delta: float) -> void:
	update_anchor()
	update_directional_view()
	apply_shadow_family()
	if sprite != null and sprite.flip_h != _last_flip_h: apply_frame()
	if Engine.is_editor_hint(): apply_profile()
	if sprite != null and profile != null:
		shadow.visible = profile.shadow_enabled and profile.category != 4 and sprite.visible

func set_directional_pose(pose: String, facing: Vector3) -> void:
	_explicit_world_facing = true
	if directional_pose != pose:
		_directions.clear()
	directional_pose = pose
	world_facing = facing
	update_directional_view()

func set_local_directional_pose(pose: String, facing: Vector3) -> void:
	# Locomotion writes actor.position in its parent's coordinates. A scene
	# preview/root actor may have a Viewport parent rather than a Node3D.
	var parent_space := get_parent().get_parent() as Node3D
	set_directional_pose(pose, parent_space.global_basis * facing if parent_space != null else facing)

func update_directional_view() -> void:
	if not sprite is AnimatedSprite3D or profile == null or directional_pose.is_empty(): return
	var animated := sprite as AnimatedSprite3D
	if _directions.is_empty():
		var prefix: String = profile.directional_animation_prefixes.get(directional_pose, "")
		_directions = ViewDirection.animation_map(animated.sprite_frames, prefix, profile.directional_aliases.get(directional_pose, {}))
	var camera := get_viewport().get_camera_3d()
	var basis := camera.global_basis if camera != null else Basis.IDENTITY
	var selected := ViewDirection.resolve(_directions, ViewDirection.sector(world_facing, basis))
	if selected.is_empty(): return
	var animation := StringName(selected.animation)
	animated.flip_h = selected.get("flip_h", false)
	if animated.animation == animation and _applied_pose == directional_pose: return
	var same_pose := _applied_pose == directional_pose
	var was_playing := animated.is_playing()
	var phase := (animated.frame + animated.frame_progress) / animated.sprite_frames.get_frame_count(animated.animation)
	animated.play(animation)
	if same_pose:
		var frame_phase := phase * animated.sprite_frames.get_frame_count(animation)
		animated.set_frame_and_progress(int(frame_phase), fmod(frame_phase, 1.0))
		if not was_playing: animated.pause()
	_applied_pose = directional_pose

func update_anchor() -> void:
	var actor := get_parent() as Node3D
	if actor != null:
		global_transform = Transform3D(Basis.IDENTITY, actor.global_position)
		if not _explicit_world_facing: world_facing = actor.global_basis.z

func apply_profile() -> void:
	if not is_node_ready() or profile == null: return
	_directions.clear()
	if directional_pose.is_empty(): directional_pose = profile.default_directional_pose
	visual_anchor.position = Vector3(0, profile.ground_lift, 0)
	visual_anchor.scale = profile.sprite_scale
	apply_shadow_family()
	shadow.visible = profile.shadow_enabled and profile.category != 4
	if sprite != null:
		sprite.position = Vector3.ZERO
		sprite.scale = Vector3.ONE
		sprite.pixel_size = profile.pixel_size
		sprite.no_depth_test = false
		if profile.flat_on_ground:
			sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		apply_frame()

func apply_frame() -> void:
	if sprite == null or profile == null: return
	if profile.flat_on_ground:
		sprite.offset = Vector2.ZERO
		return
	var texture: Texture2D
	var padding := profile.feet_from_bottom_px
	var feet_x := profile.feet_from_left_px
	if sprite is AnimatedSprite3D:
		var animated := sprite as AnimatedSprite3D
		texture = animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
		padding = float(profile.animation_feet_from_bottom_px.get(String(animated.animation), padding))
		feet_x = float(profile.animation_feet_from_left_px.get(String(animated.animation), feet_x))
	elif sprite is Sprite3D: texture = (sprite as Sprite3D).texture
	if texture != null:
		sprite.centered = true
		var x_offset := texture.get_width() * 0.5 - feet_x if feet_x >= 0 else 0.0
		if sprite.flip_h: x_offset = -x_offset
		sprite.offset = Vector2(x_offset, texture.get_height() * 0.5 - padding)
		_last_flip_h = sprite.flip_h

func apply_shadow_family() -> void:
	if profile == null or shadow == null: return
	var family := profile.resolved_shadow_family()
	var width := family.width * profile.shadow_scale_multiplier
	var depth := family.depth * profile.shadow_scale_multiplier
	if not is_equal_approx(shadow.width, width): shadow.width = width
	if not is_equal_approx(shadow.depth, depth): shadow.depth = depth
	if not is_equal_approx(shadow.opacity, family.opacity): shadow.opacity = family.opacity
	if not is_equal_approx(shadow.ground_offset, family.ground_offset): shadow.ground_offset = family.ground_offset
