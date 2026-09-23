extends Marker3D

## Frame-aware rod-tip socket for the fishing line.
##
## Ryu's fishing rod is baked into AnimatedSprite3D frames, so there is no
## physical rod bone/node to attach the line to. This marker detects the visible
## rod tip directly from the current sprite frame, caches that pixel coordinate,
## then converts it back into the billboard's 3D plane every frame.
##
## This is presentation-only. Fishing mechanics never depend on this marker.

@export_category("References")
@export var source_sprite: AnimatedSprite3D
@export var camera: Camera3D
@export var fallback_marker: Node3D

@export_category("Tip Detection")
## Pixels below this alpha are ignored while finding the outermost rod pixel.
@export_range(0.0, 1.0, 0.01)
var alpha_threshold: float = 0.10

## Search origin inside each 192x160 fishing frame. The rod is the feature that
## extends farthest from this character-centred point across the fishing poses.
@export var detection_center_ratio: Vector2 = Vector2(0.50, 0.60)

## Pull the attachment a fraction of a pixel back into the painted rod so the
## generated line visually touches the final rod pixel instead of hovering just
## beyond it.
@export_range(0.0, 4.0, 0.05)
var tip_inset_pixels: float = 0.75

## Small art-direction correction if the automatically detected socket ever
## needs a couple of screen pixels of adjustment. Normally leave at zero.
@export var pixel_correction: Vector2 = Vector2.ZERO

## Only these animation families are expected to contain a useful fishing rod
## while an active bait exists. Unknown animations fall back to BaitSpawner.
@export var tracked_animation_prefixes: PackedStringArray = PackedStringArray([
	"Throw",
	"Reel"
])

var _tip_cache: Dictionary = {}
var _frame_size_cache: Dictionary = {}
var _failed_frame_cache: Dictionary = {}


func _ready() -> void:
	# Camera + BaitSpawner update at priority 100; FishingLineView updates at 110.
	# Sit between them so the line always receives this frame's final rod socket.
	process_priority = 105
	_update_tip_world_position()


func _process(_delta: float) -> void:
	_update_tip_world_position()


func clear_cache() -> void:
	_tip_cache.clear()
	_frame_size_cache.clear()
	_failed_frame_cache.clear()


func _update_tip_world_position() -> void:
	if not is_instance_valid(source_sprite) or not is_instance_valid(camera):
		_use_fallback()
		return

	if not _should_track_animation(source_sprite.animation):
		_use_fallback()
		return

	var frame_info: Dictionary = _get_frame_tip_info(
		source_sprite.animation,
		source_sprite.frame
	)

	if frame_info.is_empty():
		_use_fallback()
		return

	var tip_pixel: Vector2 = frame_info["tip"]
	var frame_size: Vector2 = frame_info["size"]

	if source_sprite.flip_h:
		tip_pixel.x = frame_size.x - 1.0 - tip_pixel.x

	if source_sprite.flip_v:
		tip_pixel.y = frame_size.y - 1.0 - tip_pixel.y

	var pixel_offset: Vector2 = tip_pixel

	if source_sprite.centered:
		pixel_offset -= frame_size * 0.5

	pixel_offset += source_sprite.offset
	pixel_offset += pixel_correction

	var world_scale: Vector3 = source_sprite.global_transform.basis.get_scale()
	var horizontal_world: float = (
		pixel_offset.x
		* source_sprite.pixel_size
		* world_scale.x
	)
	var vertical_world: float = (
		pixel_offset.y
		* source_sprite.pixel_size
		* world_scale.y
	)

	# AnimatedSprite3D is full-billboarded in this project. Its rendered texture
	# plane therefore uses the active camera's right/up axes rather than the
	# CharacterBody3D's world rotation.
	var camera_right: Vector3 = camera.global_transform.basis.x.normalized()
	var camera_up: Vector3 = camera.global_transform.basis.y.normalized()

	global_position = (
		source_sprite.global_position
		+ camera_right * horizontal_world
		- camera_up * vertical_world
	)


func _should_track_animation(animation_name: StringName) -> bool:
	var current: String = String(animation_name)

	for prefix: String in tracked_animation_prefixes:
		if current.begins_with(prefix):
			return true

	return false


func _get_frame_tip_info(
	animation_name: StringName,
	frame_index: int
) -> Dictionary:
	var key: String = "%s:%d" % [String(animation_name), frame_index]

	if _tip_cache.has(key):
		return {
			"tip": _tip_cache[key],
			"size": _frame_size_cache[key]
		}

	# If this particular texture/frame could not be inspected, do not retry it
	# every process tick. The fallback marker will be used instead.
	if _failed_frame_cache.has(key):
		return {}

	if source_sprite.sprite_frames == null:
		_failed_frame_cache[key] = true
		return {}

	if not source_sprite.sprite_frames.has_animation(animation_name):
		_failed_frame_cache[key] = true
		return {}

	var frame_count: int = source_sprite.sprite_frames.get_frame_count(
		animation_name
	)

	if frame_index < 0 or frame_index >= frame_count:
		_failed_frame_cache[key] = true
		return {}

	var texture: Texture2D = source_sprite.sprite_frames.get_frame_texture(
		animation_name,
		frame_index
	)

	if texture == null:
		_failed_frame_cache[key] = true
		return {}

	var image: Image
	var region_position := Vector2i.ZERO
	var region_size := Vector2i.ZERO

	if texture is AtlasTexture:
		var atlas_texture := texture as AtlasTexture

		if atlas_texture.atlas == null:
			_failed_frame_cache[key] = true
			return {}

		image = atlas_texture.atlas.get_image()
		region_position = Vector2i(
			int(round(atlas_texture.region.position.x)),
			int(round(atlas_texture.region.position.y))
		)
		region_size = Vector2i(
			int(round(atlas_texture.region.size.x)),
			int(round(atlas_texture.region.size.y))
		)
	else:
		image = texture.get_image()

		if image != null:
			region_size = Vector2i(image.get_width(), image.get_height())

	if image == null or image.is_empty():
		_failed_frame_cache[key] = true
		return {}

	# Imported Godot textures may return GPU-compressed Images. get_pixel()
	# cannot read those directly, so convert them to a CPU-readable format once
	# before scanning the alpha channel.
	if image.is_compressed():
		var decompress_result: Error = image.decompress()
		if decompress_result != OK:
			_failed_frame_cache[key] = true
			return {}

	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	if region_size.x <= 0 or region_size.y <= 0:
		_failed_frame_cache[key] = true
		return {}

	var search_center := Vector2(
		float(region_size.x) * detection_center_ratio.x,
		float(region_size.y) * detection_center_ratio.y
	)

	var best_pixel := Vector2.ZERO
	var best_distance_squared: float = -1.0
	var found_pixel: bool = false

	for y: int in range(region_size.y):
		for x: int in range(region_size.x):
			var atlas_x: int = region_position.x + x
			var atlas_y: int = region_position.y + y

			if atlas_x < 0 or atlas_y < 0:
				continue

			if atlas_x >= image.get_width() or atlas_y >= image.get_height():
				continue

			if image.get_pixel(atlas_x, atlas_y).a < alpha_threshold:
				continue

			var candidate := Vector2(float(x), float(y))
			var distance_squared: float = candidate.distance_squared_to(
				search_center
			)

			if distance_squared > best_distance_squared:
				best_distance_squared = distance_squared
				best_pixel = candidate
				found_pixel = true

	if not found_pixel:
		_failed_frame_cache[key] = true
		return {}

	if tip_inset_pixels > 0.0:
		best_pixel = best_pixel.move_toward(search_center, tip_inset_pixels)

	var frame_size := Vector2(float(region_size.x), float(region_size.y))
	_tip_cache[key] = best_pixel
	_frame_size_cache[key] = frame_size

	return {
		"tip": best_pixel,
		"size": frame_size
	}


func _use_fallback() -> void:
	if is_instance_valid(fallback_marker):
		global_position = fallback_marker.global_position
