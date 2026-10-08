@tool
extends Node3D
class_name GroundPresentation
## A root-relative physical feet anchor, shared across all grounded sheets.
## Sprite frame padding changes pixel alignment, never the world feet point.
@export var profile: WorldActorPresentationProfile
@onready var visual_anchor: Node3D = $VisualAnchor
@onready var shadow: WorldBlobShadow = $ShadowAnchor/WorldBlobShadow
var sprite: SpriteBase3D

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

func _process(_delta: float) -> void:
	update_anchor()
	if Engine.is_editor_hint(): apply_profile()
	if sprite != null and profile != null:
		shadow.visible = profile.shadow_enabled and profile.category != 4 and sprite.visible

func update_anchor() -> void:
	var actor := get_parent() as Node3D
	if actor != null: global_transform = Transform3D(Basis.IDENTITY, actor.global_position)

func apply_profile() -> void:
	if not is_node_ready() or profile == null: return
	visual_anchor.position = Vector3(0, profile.ground_lift, 0)
	visual_anchor.scale = profile.sprite_scale
	shadow.width = profile.shadow_width
	shadow.depth = profile.shadow_depth
	shadow.opacity = profile.shadow_opacity
	shadow.ground_offset = profile.shadow_ground_lift
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
	if sprite is AnimatedSprite3D:
		var animated := sprite as AnimatedSprite3D
		texture = animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
		padding = float(profile.animation_feet_from_bottom_px.get(String(animated.animation), padding))
	elif sprite is Sprite3D: texture = (sprite as Sprite3D).texture
	if texture != null:
		sprite.centered = true
		sprite.offset = Vector2(0, texture.get_height() * 0.5 - padding)
