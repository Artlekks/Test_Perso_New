extends CanvasLayer
class_name FishingTechniqueView

@onready var bubble: TextureRect = $Root/TechniqueBubble

@export_category("Technique Bubble Textures")
@export var tec_1_texture: Texture2D
@export var tec_2_texture: Texture2D
@export var tec_3_texture: Texture2D
@export var tec_4_texture: Texture2D

@export_category("Presentation")
@export var display_time: float = 0.65
@export var fade_time: float = 0.15

## Pixel offset after projecting the bait's water-surface position.
## Y is intentionally slightly negative so the bubble sits just above
## the water rather than directly on top of the bait point.
@export var screen_offset: Vector2 = Vector2(0.0, -8.0)

## Small world-space lift above the water surface before projection.
@export var surface_world_offset_y: float = 0.08

var _tween: Tween = null
var _follow_target: Node3D = null
var _is_displaying: bool = false


func _ready() -> void:
	bubble.hide()
	bubble.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	if not _is_displaying:
		return

	_update_follow_position()


func show_tech(
	level: int,
	follow_target: Node3D = null
) -> void:
	if level < 1 or level > 4:
		return

	var texture := _get_tech_texture(level)

	if texture == null:
		return

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_follow_target = follow_target
	_is_displaying = true

	bubble.texture = texture
	bubble.modulate.a = 1.0
	bubble.show()

	_update_follow_position()

	_tween = create_tween()
	_tween.tween_interval(display_time)
	_tween.tween_property(
		bubble,
		"modulate:a",
		0.0,
		fade_time
	)
	_tween.tween_callback(_hide)


func clear() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = null
	_hide()


func _hide() -> void:
	_is_displaying = false
	_follow_target = null
	bubble.hide()
	bubble.modulate.a = 1.0


func _update_follow_position() -> void:
	if not is_instance_valid(_follow_target):
		_hide()
		return

	var camera := get_viewport().get_camera_3d()

	if camera == null:
		bubble.hide()
		return

	# Follow the bait horizontally, but project from the WATER SURFACE.
	# This means a sinking lure does not drag the bubble underwater.
	var marker_world_position := _follow_target.global_position

	# Ask the bait through a tiny public interface instead of reaching
	# into one of its internal variables by string name.
	if _follow_target.has_method("get_water_surface_y"):
		marker_world_position.y = (
			float(
				_follow_target.get_water_surface_y()
			)
			+ surface_world_offset_y
		)

	if camera.is_position_behind(marker_world_position):
		bubble.hide()
		return

	var screen_position := camera.unproject_position(
		marker_world_position
	)

	var scaled_size := Vector2(
		bubble.size.x * absf(bubble.scale.x),
		bubble.size.y * absf(bubble.scale.y)
	)

	# Center horizontally over the bait and put the bottom of the bubble
	# just above the projected water-surface point.
	bubble.global_position = (
		screen_position
		+ screen_offset
		- Vector2(
			scaled_size.x * 0.5,
			scaled_size.y
		)
	)

	bubble.show()


func _get_tech_texture(level: int) -> Texture2D:
	match level:
		1:
			return tec_1_texture
		2:
			return tec_2_texture
		3:
			return tec_3_texture
		4:
			return tec_4_texture
		_:
			return null
