extends Node3D

@onready var ripple_sprite: AnimatedSprite3D = $RippleSprite

@export var surface_offset: float = 0.02
## Fixed-size surface cue: explicitly readable at native/mobile viewport sizes.
@export var ripple_pixel_size: float = 0.0035

@export_category("Bite Surface Sprite")
@export var bite_sheet: Texture2D = preload(
	"res://assets/sprites/fishing/bait/bait_bite_sheet.png"
)
@export_range(1.0, 30.0, 1.0)
var bite_animation_fps: float = 12.0
@export_range(0.001, 0.05, 0.0005)
var bite_pixel_size: float = 0.014
@export var separator_color: Color = Color(1.0, 0.0, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01)
var separator_threshold: float = 0.75
@export_range(0.0, 1.0, 0.01)
var separator_tolerance: float = 0.18

var follow_target: Node3D = null
var surface_y: float = 0.0
var active: bool = false
var _frames_ready: bool = false
var _surface_frames: SpriteFrames
static var _ripple_frames_cache: Dictionary = {}


func _ready() -> void:
	top_level = true
	# Surface projection follows the final screen-constrained waterborne bait.
	process_priority = 105
	visible = false
	set_process(false)
	var authored := ripple_sprite.sprite_frames
	var cache_key := authored.resource_path
	if _ripple_frames_cache.has(cache_key):
		_surface_frames = _ripple_frames_cache[cache_key].duplicate()
	else:
		_surface_frames = authored.duplicate(true)
		_surface_frames.set_animation_loop(&"Ripple", false)
		# Slice after decompression: AtlasTexture.get_image() cannot crop the
		# VRAM-compressed source on rendered backends. Small frame textures also
		# avoid depending on the 11904px sheet fitting a mobile GPU's atlas limit.
		var first: AtlasTexture = _surface_frames.get_frame_texture(&"Ripple", 0)
		var sheet_image := first.atlas.get_image()
		if sheet_image.is_compressed():
			sheet_image.decompress()
		for index in _surface_frames.get_frame_count(&"Ripple"):
			var texture: AtlasTexture = _surface_frames.get_frame_texture(&"Ripple", index)
			var image := sheet_image.get_region(Rect2i(texture.region))
			_surface_frames.set_frame(&"Ripple", index, ImageTexture.create_from_image(image),
				_surface_frames.get_frame_duration(&"Ripple", index))
		_ripple_frames_cache[cache_key] = _surface_frames.duplicate()
	ripple_sprite.animation_finished.connect(hide_ripple)
	_setup_sprite()
	_ensure_frames()


func configure(
	target: Node3D,
	water_surface_y: float
) -> void:
	follow_target = target
	surface_y = water_surface_y

	_update_position()


func show_ripple(opportunity_duration: float = 0.0) -> void:
	if not is_instance_valid(follow_target):
		return

	_ensure_frames()

	active = true
	visible = true
	set_process(true)

	_update_position()
	ripple_sprite.stop()
	ripple_sprite.frame = 0
	ripple_sprite.speed_scale = 1.0
	if opportunity_duration > 0.0:
		ripple_sprite.speed_scale = get_authored_ripple_duration() / opportunity_duration
	ripple_sprite.pixel_size = ripple_pixel_size
	ripple_sprite.play(&"Ripple")


func show_bite_splash() -> void:
	if not is_instance_valid(follow_target):
		return
	_ensure_frames()
	active = true
	visible = true
	set_process(true)
	_update_position()
	ripple_sprite.stop()
	ripple_sprite.frame = 0
	ripple_sprite.speed_scale = 1.0
	ripple_sprite.pixel_size = bite_pixel_size
	ripple_sprite.play(&"BiteSplash")


func hide_ripple(preserve_committed_splash: bool = false) -> void:
	if preserve_committed_splash and active and ripple_sprite.animation == &"BiteSplash":
		return
	active = false
	visible = false
	set_process(false)

	ripple_sprite.stop()
	ripple_sprite.frame = 0
	ripple_sprite.speed_scale = 1.0


func get_authored_ripple_duration() -> float:
	var frames := ripple_sprite.sprite_frames
	var duration := 0.0
	for index in frames.get_frame_count(&"Ripple"):
		duration += frames.get_frame_duration(&"Ripple", index)
	return duration / frames.get_animation_speed(&"Ripple")


func _process(_delta: float) -> void:
	if not active:
		return

	if not is_instance_valid(follow_target):
		hide_ripple()
		return

	_update_position()


func _update_position() -> void:
	if not is_instance_valid(follow_target):
		return

	var target_position: Vector3 = follow_target.global_position
	var visual_surface_y: float = surface_y + surface_offset
	var camera: Camera3D = get_viewport().get_camera_3d()

	# The bite sprite is a SURFACE effect, but the lure can be metres underwater.
	# Match the lure head's screen position back onto the water plane so the
	# sprite remains visually glued to the bait on screen.
	if camera == null:
		global_position = Vector3(
			target_position.x,
			visual_surface_y,
			target_position.z
		)
		return

	var screen_position: Vector2 = camera.unproject_position(target_position)
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)

	if absf(ray_direction.y) <= 0.00001:
		global_position = Vector3(
			target_position.x,
			visual_surface_y,
			target_position.z
		)
		return

	var distance_along_ray: float = (visual_surface_y - ray_origin.y) / ray_direction.y

	if distance_along_ray < 0.0:
		global_position = Vector3(
			target_position.x,
			visual_surface_y,
			target_position.z
		)
		return

	var projected: Vector3 = ray_origin + ray_direction * distance_along_ray
	projected.y = visual_surface_y
	global_position = projected


func _setup_sprite() -> void:
	ripple_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ripple_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ripple_sprite.no_depth_test = true
	ripple_sprite.fixed_size = true
	ripple_sprite.pixel_size = bite_pixel_size
	ripple_sprite.shaded = false
	ripple_sprite.double_sided = true
	if ripple_sprite.has_method("set_cast_shadows_setting"):
		ripple_sprite.set_cast_shadows_setting(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func _ensure_frames() -> void:
	if _frames_ready:
		return

	if bite_sheet == null:
		return

	# Preserve the authored fish_ripple.png animation; the stronger sheet is
	# a separate, non-looping committed-bite cue, never a nibble replacement.
	var frames := _surface_frames
	frames.add_animation(&"BiteSplash")
	frames.set_animation_speed(&"BiteSplash", bite_animation_fps)
	frames.set_animation_loop(&"BiteSplash", false)

	for frame_texture in _slice_sheet_to_frames(bite_sheet):
		frames.add_frame(&"BiteSplash", frame_texture)

	if frames.get_frame_count(&"BiteSplash") <= 0:
		return

	ripple_sprite.sprite_frames = frames
	ripple_sprite.animation = &"Ripple"
	ripple_sprite.pixel_size = bite_pixel_size
	_frames_ready = true


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
