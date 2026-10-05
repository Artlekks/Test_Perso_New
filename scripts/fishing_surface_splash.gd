extends Node3D

## Sprite-sheet replacement for the placeholder landing/fight splash.
## Landing uses the water-entry ripple sheet once.
## Fight splash uses the thrash sheet once and can follow the bait head's
## projected surface position for readability.

@export_category("Timing / Placement")
@export var surface_offset: float = 0.018
@export var landing_surface_y_bias: float = 0.00
@export var fight_surface_y_bias: float = 0.025

@export_category("Landing Sheet")
@export var landing_sheet: Texture2D = preload(
	"res://assets/sprites/fishing/bait/bait_landing_sheet.png"
)
@export_range(1.0, 30.0, 1.0)
var landing_animation_fps: float = 14.0
@export_range(0.001, 0.05, 0.0005)
var landing_pixel_size: float = 0.012

@export_category("Fight Thrash Sheet")
@export var fight_sheet: Texture2D = preload(
	"res://assets/sprites/fishing/bait/bait_thrash_sheet.png"
)
@export_range(1.0, 30.0, 1.0)
var fight_animation_fps: float = 12.0
@export_range(0.001, 0.05, 0.0005)
var fight_pixel_size: float = 0.006

@export_category("Sheet Slicing")
@export var separator_color: Color = Color(1.0, 0.0, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01)
var separator_threshold: float = 0.75
@export_range(0.0, 1.0, 0.01)
var separator_tolerance: float = 0.18

var _fight_variant: bool = false
var _follow_target: Node3D = null
var _follow_surface_y: float = 0.0
var _sprite: AnimatedSprite3D = null
var _landing_frames: SpriteFrames = null
var _fight_frames: SpriteFrames = null


func _ready() -> void:
	top_level = true
	visible = false
	set_process(false)
	_ensure_sprite()


func configure(
	world_position: Vector3,
	strength: float,
	fight_variant: bool
) -> void:
	_fight_variant = fight_variant
	_follow_target = null
	rotation = Vector3.ZERO
	rotation.y = randf_range(-PI, PI)
	global_position = world_position + Vector3.UP * surface_offset
	_follow_surface_y = global_position.y - surface_offset
	visible = true
	_apply_animation(maxf(strength, 0.05))
	set_process(_fight_variant)


func set_follow_target(target: Node3D) -> void:
	if not is_instance_valid(target):
		_follow_target = null
		set_process(false)
		return

	_follow_target = target
	_follow_surface_y = global_position.y - surface_offset
	if _fight_variant:
		set_process(true)
		_update_follow_anchor()


func _process(_delta: float) -> void:
	_update_follow_anchor()


func _ensure_sprite() -> void:
	if is_instance_valid(_sprite):
		return

	_sprite = AnimatedSprite3D.new()
	_sprite.name = "EffectSprite"
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.no_depth_test = true
	_sprite.fixed_size = true
	_sprite.shaded = false
	_sprite.double_sided = true
	if _sprite.has_method("set_cast_shadows_setting"):
		_sprite.set_cast_shadows_setting(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_sprite.animation_finished.connect(_on_animation_finished)
	add_child(_sprite)


func _apply_animation(strength: float) -> void:
	_ensure_sprite()

	var frames: SpriteFrames = _get_frames_for_current_variant()
	if frames == null:
		queue_free()
		return

	_sprite.stop()
	_sprite.sprite_frames = frames
	_sprite.animation = &"Effect"
	_sprite.frame = 0
	_sprite.pixel_size = fight_pixel_size if _fight_variant else landing_pixel_size
	_sprite.scale = Vector3.ONE * _get_strength_scale(strength)
	_sprite.play(&"Effect")


func _get_strength_scale(strength: float) -> float:
	if _fight_variant:
		return clampf(0.85 + strength * 0.18, 0.85, 1.20)
	return clampf(0.95 + strength * 0.22, 0.95, 1.30)


func _get_frames_for_current_variant() -> SpriteFrames:
	if _fight_variant:
		if _fight_frames == null:
			_fight_frames = _build_frames(fight_sheet, fight_animation_fps, false)
		return _fight_frames

	if _landing_frames == null:
		_landing_frames = _build_frames(landing_sheet, landing_animation_fps, false)
	return _landing_frames


func _build_frames(
	sheet: Texture2D,
	fps: float,
	looping: bool
) -> SpriteFrames:
	if sheet == null:
		return null

	var frames := SpriteFrames.new()
	frames.add_animation(&"Effect")
	frames.set_animation_speed(&"Effect", fps)
	frames.set_animation_loop(&"Effect", looping)

	for frame_texture in _slice_sheet_to_frames(sheet):
		frames.add_frame(&"Effect", frame_texture)

	if frames.get_frame_count(&"Effect") <= 0:
		return null

	return frames


func _slice_sheet_to_frames(sheet: Texture2D) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	if sheet == null:
		return result

	var image: Image = sheet.get_image()
	if image == null or image.is_empty():
		return result

	var width: int = image.get_width()
	var height: int = image.get_height()
	var separators: Array[int] = []

	for x in range(width):
		if _is_separator_column(image, x, height):
			separators.append(x)

	var start_x: int = 0
	for separator_x in separators:
		var frame_width: int = separator_x - start_x
		if frame_width > 0:
			result.append(_crop_texture(image, Rect2i(start_x, 0, frame_width, height)))
		start_x = separator_x + 1

	if start_x < width:
		result.append(_crop_texture(image, Rect2i(start_x, 0, width - start_x, height)))

	return result


func _is_separator_column(image: Image, x: int, height: int) -> bool:
	var matching_pixels: int = 0

	for y in range(height):
		var color: Color = image.get_pixel(x, y)
		if color.a < 0.8:
			continue
		if _is_separator_color(color):
			matching_pixels += 1

	return float(matching_pixels) >= float(height) * separator_threshold


func _is_separator_color(color: Color) -> bool:
	return (
		absf(color.r - separator_color.r) <= separator_tolerance
		and absf(color.g - separator_color.g) <= separator_tolerance
		and absf(color.b - separator_color.b) <= separator_tolerance
	)


func _crop_texture(image: Image, rect: Rect2i) -> Texture2D:
	var cropped: Image = image.get_region(rect)
	return ImageTexture.create_from_image(cropped)


func _update_follow_anchor() -> void:
	if not _fight_variant or not is_instance_valid(_follow_target):
		return

	var bait_position: Vector3 = _follow_target.global_position
	var surface_y: float = _follow_surface_y

	# Prefer the lure's real water height if exposed by the bait runtime.
	if _follow_target.has_method("get_water_surface_y"):
		surface_y = float(_follow_target.get_water_surface_y()) + fight_surface_y_bias
	else:
		surface_y += fight_surface_y_bias

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		global_position = Vector3(
			bait_position.x,
			surface_y + surface_offset,
			bait_position.z
		)
		return

	var screen_position: Vector2 = camera.unproject_position(bait_position)
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)

	if absf(ray_direction.y) <= 0.00001:
		return

	var distance_along_ray: float = (surface_y - ray_origin.y) / ray_direction.y
	if distance_along_ray < 0.0:
		return

	var projected: Vector3 = ray_origin + ray_direction * distance_along_ray
	projected.y = surface_y + surface_offset
	global_position = projected


func _on_animation_finished() -> void:
	queue_free()
