extends RefCounted
## Shared visible-artwork contract; the notifier and feet are not sufficient.
## Cache alpha-tight sprite footprints, including rods and transparent margins.
static var _sprite_opaque_bounds_cache: Dictionary = {}

static func is_player_view_ready(
		notifier: VisibleOnScreenNotifier3D, camera: Camera3D
) -> bool:
	if not is_instance_valid(notifier) or not is_instance_valid(camera):
		return false
	var player: Node3D = notifier.get_parent() as Node3D
	if not is_instance_valid(player):
		return false
	var sprite: GeometryInstance3D = player.get_node_or_null(
		"GroundPresentation/VisualAnchor/AnimatedSprite3D") as GeometryInstance3D
	if is_instance_valid(sprite):
		if not sprite.is_visible_in_tree():
			return false
		return is_geometry_projected_in_view(sprite,camera)
	# Synthetic scene/QAs without player artwork: fall back to notifier volume,
	# NOT notifier.is_on_screen() (it is updated asynchronously).
	return is_box_projected_in_view(notifier.global_transform,notifier.aabb,camera)


static func is_geometry_projected_in_view(geometry: GeometryInstance3D, camera: Camera3D) -> bool:
	if not is_instance_valid(geometry) or not is_instance_valid(camera):
		return false
	# AnimatedSprite3D in the live player scene has billboard=1. Its rendered
	# quad rotates toward the lens in the shader, not in global_transform; a
	# naive projection of local AABB corners can miss its first visible pixels.
	if geometry is SpriteBase3D:
		return is_billboard_art_projected_in_view(geometry as SpriteBase3D,camera)
	return is_box_projected_in_view(geometry.global_transform,geometry.get_aabb(),camera)


static func is_billboard_art_projected_in_view(sprite: SpriteBase3D, camera: Camera3D) -> bool:
	# The authored player Sprite3D billboards toward the camera. Project its
	# actual rectangular frame in CAMERA axes; using a sphere hides the inset
	# several dozen pixels too early on some window sizes.
	if sprite.billboard == BaseMaterial3D.BILLBOARD_DISABLED:
		return is_box_projected_in_view(sprite.global_transform,sprite.get_aabb(),camera)
	var bounds: AABB = sprite.get_aabb()
	# get_aabb() contains transparent sprite-sheet padding. That padding
	# triggered the handoff well before the first actual painted pixel, leaving
	# no world fisherman AND no HUD fisherman (the reported missing inset).
	if sprite is AnimatedSprite3D:
		var animated: AnimatedSprite3D = sprite as AnimatedSprite3D
		if animated.sprite_frames != null:
			var texture: Texture2D = animated.sprite_frames.get_frame_texture(animated.animation,animated.frame)
			if texture != null:
				var id: int = texture.get_instance_id()
				if not _sprite_opaque_bounds_cache.has(id):
					# Imported frame textures may be VRAM-compressed. Image.get_used_rect()
					# calls blit_rect internally and errors on compressed images each
					# frame; decompress the IMAGE COPY before inspecting alpha bounds.
					# When decompression is unavailable, use the full quad conservatively
					# (hide inset early, never display both character versions).
					var full: Rect2i = Rect2i(Vector2i.ZERO,Vector2i(texture.get_size()))
					var used: Rect2i = full
					var raw_image: Image = texture.get_image()
					if raw_image != null:
						var readable: bool = true
						if raw_image.is_compressed():
							readable = raw_image.decompress() == OK
						if readable and not raw_image.is_compressed():
							used = raw_image.get_used_rect()
					_sprite_opaque_bounds_cache[id] = Rect2(Vector2(used.position),Vector2(used.size))
				var occupied: Rect2 = _sprite_opaque_bounds_cache[id]
				var dimensions: Vector2 = texture.get_size()
				if not occupied.has_area():
					return false
				if dimensions.x > 0.0 and dimensions.y > 0.0:
					var start_x: float = occupied.position.x / dimensions.x
					var end_x: float = occupied.end.x / dimensions.x
					var start_y: float = 1.0-occupied.end.y / dimensions.y
					var end_y: float = 1.0-occupied.position.y / dimensions.y
					var old: AABB = bounds
					bounds = AABB(
						Vector3(old.position.x+old.size.x*start_x, old.position.y+old.size.y*start_y, old.position.z),
						Vector3(old.size.x*(end_x-start_x), old.size.y*(end_y-start_y), old.size.z))
	var scale: Vector3 = sprite.global_transform.basis.get_scale()
	var center: Vector3 = sprite.global_position
	center += camera.global_basis.x*bounds.get_center().x*scale.x
	center += camera.global_basis.y*bounds.get_center().y*scale.y
	center += camera.global_basis.z*bounds.get_center().z*scale.z
	var horizontal: Vector3 = camera.global_basis.x*bounds.size.x*.5*scale.x
	var vertical: Vector3 = camera.global_basis.y*bounds.size.y*.5*scale.y
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	var any_forward: bool = false
	for x in [-1.0,1.0]:
		for y in [-1.0,1.0]:
			var corner: Vector3 = center+horizontal*x+vertical*y
			if camera.is_position_behind(corner):
				continue
			var pixel: Vector2 = camera.unproject_position(corner)
			if not pixel.is_finite():
				continue
			any_forward = true
			low = low.min(pixel)
			high = high.max(pixel)
	if not any_forward:
		return false
	return Rect2(low,high-low).intersects(Rect2(Vector2.ZERO,size),true)


static func is_box_projected_in_view(transform: Transform3D, bounds: AABB, camera: Camera3D) -> bool:
	# Test ALL artwork bounds, including a one-pixel visible edge; the previous
	# center/feet threshold waited until 10% inside and displayed both figures.
	# Projecting an AABB is conservative for billboards/partly transparent sprites.
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	if size.x < 1.0 or size.y < 1.0:
		return false
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	var valid := false
	for x in [0.0,1.0]:
		for y in [0.0,1.0]:
			for z in [0.0,1.0]:
				var local := bounds.position + bounds.size*Vector3(x,y,z)
				var world: Vector3 = transform*local
				if camera.is_position_behind(world):
					continue
				var point := camera.unproject_position(world)
				if not point.is_finite():
					continue
				low = low.min(point)
				high = high.max(point)
				valid = true
	if not valid:
		return false
	# The full screen rectangle includes its very first and last pixel.
	return Rect2(low,high-low).intersects(Rect2(Vector2.ZERO,size),true)


# Retained as a pure helper for the older gate/QAs, NOT for handoff decisions.
static func is_player_projection_ready(foot_uv: Vector2) -> bool:
	return (foot_uv.x >= 0.10 and foot_uv.x <= 0.90
		and foot_uv.y >= 0.19 and foot_uv.y <= 0.91)

static func is_rod_projection_inside_frame(screen: Vector2, dimensions: Vector2) -> bool:
	return (screen.x >= 0.0 and screen.x <= dimensions.x
		and screen.y >= 0.0 and screen.y <= dimensions.y)

static func is_rod_visible(notifier: VisibleOnScreenNotifier3D, camera: Camera3D) -> bool:
	return is_player_view_ready(notifier,camera)
