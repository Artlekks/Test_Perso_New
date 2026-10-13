extends Node3D
## Ambient rain is world-owned, independent of casting or fishing mode.
## Rain and water/ground impact visuals are presentation only.
## Rainfall uses two camera-centered GPU layers with pixel-art drop textures.
## All surface impacts use ONLY the small five-frame TOP ROW of RainImpact.png.

const SPLASH_ATLAS: Texture2D = preload("res://assets/ui/environment/RainImpact.png")
const POLL_SECONDS: float = 0.5

@export_category("Rain Mode")
@export_enum("Auto", "Clear", "Rain Preview", "Storm Preview") var weather_mode: int = 0
@export var enabled: bool = true

@export_category("Rainfall")
@export_range(24, 600, 1) var drop_count: int = 220
@export_range(0.002, 0.04, 0.001) var drop_width: float = 0.010
@export_range(0.025, 0.28, 0.005) var drop_length: float = 0.095
@export_range(0.05, 1.0, 0.05) var drop_opacity: float = 0.46
@export var rain_color: Color = Color(0.67, 0.86, 1.0, 1.0)
@export_range(2.0, 24.0, 0.5) var visible_width: float = 6.0
@export_range(2.0, 24.0, 0.5) var visible_depth: float = 6.0
@export_range(1.0, 12.0, 0.25) var camera_focus_distance: float = 4.0
@export_range(2.0, 12.0, 0.25) var spawn_height_above_camera: float = 4.0
@export_range(0.1, 0.9, 0.05) var distant_rain_share: float = 0.45

@export_category("Surface Ripples - Top Row Only")
@export_range(0.001, 0.04, 0.001) var splash_pixel_size: float = 0.005
@export_range(1.0, 30.0, 1.0) var splash_fps: float = 12.0
@export_range(1.0, 300.0, 1.0) var splash_rate_per_second: float = 160.0
@export_range(1, 200, 1) var max_simultaneous_splashes: int = 100
@export var splash_color: Color = Color.WHITE
@export_range(0.0, 1.0, 0.01) var splash_opacity: float = 0.8

var _weather_timer: float = 0.0
var _impact_timer: float = 0.0
var _raining: bool = false
var _storm: bool = false
var _rain_particles: GPUParticles3D = null
var _distant_rain_particles: GPUParticles3D = null
var _drop_texture: Texture2D = null
var _beach: MeshInstance3D = null
var _sea: MeshInstance3D = null
var _splash_frames: SpriteFrames = null
var _splashes: Array[AnimatedSprite3D] = []
var _splash_pool: Array[AnimatedSprite3D] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_create_rainfall()
	_build_splash_frames()
	_poll_weather()
	set_process(true)

func _process(delta: float) -> void:
	_weather_timer += delta
	if _weather_timer >= POLL_SECONDS:
		_weather_timer = 0.0
		_poll_weather()
	if not _raining:
		return
	_follow_camera()
	# Five frames at 12 FPS last about 0.42 seconds. ~160 starts/second
	# yields roughly 65-70 overlapping tiny ripples (more during storms).
	# Accumulate elapsed time instead of resetting the timer each frame.
	var rate: float = maxf(1.0, splash_rate_per_second) * (1.3 if _storm else 1.0)
	var interval: float = 1.0 / rate
	_impact_timer = minf(_impact_timer + delta, 0.25)
	var spawn_budget: int = 12 # Prevent frame stalls when resuming after a pause.
	while _impact_timer >= interval and spawn_budget > 0:
		_impact_timer -= interval
		spawn_budget -= 1
		if _splashes.size() >= max_simultaneous_splashes:
			break
		_spawn_impact()

func _resolve_weather(tags: PackedStringArray) -> String:
	if not enabled or weather_mode == 1:
		return "clear"
	if weather_mode == 2:
		return "rain"
	if weather_mode == 3:
		return "storm"
	if tags.has("tempest") or tags.has("storm"):
		return "storm"
	if tags.has("rain"):
		return "rain"
	return "clear"

func _poll_weather() -> void:
	var tags: PackedStringArray = PackedStringArray()
	var game: Node = get_parent().get_parent() if get_parent() != null else null
	var fishing: Node = game.get_node_or_null("Game/Fishing") if game != null else null
	if fishing != null:
		var environment: Node = fishing.get("fishing_environment_service") as Node
		if environment != null and environment.has_method("get_active_tags"):
			tags = environment.call("get_active_tags") as PackedStringArray
	var state: String = _resolve_weather(tags)
	_raining = state != "clear"
	_storm = state == "storm"
	if _rain_particles != null:
		_rain_particles.emitting = _raining
	if _distant_rain_particles != null:
		_distant_rain_particles.emitting = _raining
	_apply_wind_drift()

func _create_rainfall() -> void:
	# Godot's particle docs recommend a process material and a small draw-pass
	# mesh. A tiny alpha-gradient texture makes the particles taper instead
	# of reading as opaque grey rods at the project's close-up camera scale.
	_drop_texture = _create_drop_texture()
	var distant_count: int = maxi(1, roundi(float(drop_count) * distant_rain_share))
	var near_count: int = maxi(1, drop_count - distant_count)
	_rain_particles = _make_rain_layer(
		&"NearRain", near_count, drop_width, drop_length, drop_opacity, 1.0
	)
	_distant_rain_particles = _make_rain_layer(
		&"DistantRain", distant_count, drop_width * 0.72,
		drop_length * 0.60, drop_opacity * 0.52, 1.15
	)

func _create_drop_texture() -> Texture2D:
	# A five-pixel-wide, tapered sprite: transparent ends, thin pale center.
	# It intentionally does not replace either of your rain-impact sprites.
	var picture: Image = Image.create(5, 15, false, Image.FORMAT_RGBA8)
	for y in range(15):
		var progress: float = float(y) / 14.0
		var taper: float = pow(sin(PI * progress), 1.3)
		for x in range(5):
			var center_weight: float = 1.0 if x == 2 else (0.28 if x == 1 or x == 3 else 0.0)
			picture.set_pixel(x, y, Color(1.0, 1.0, 1.0, taper * center_weight))
	return ImageTexture.create_from_image(picture)

func _make_rain_layer(
	layer_name: StringName, amount: int, width: float,
	length: float, alpha: float, spread_scale: float
) -> GPUParticles3D:
	var layer: GPUParticles3D = GPUParticles3D.new()
	layer.name = String(layer_name)
	layer.amount = amount
	layer.lifetime = 1.15
	layer.preprocess = 0.65
	layer.explosiveness = 0.0
	layer.randomness = 0.24
	layer.local_coords = false
	layer.emitting = false
	layer.visibility_aabb = AABB(Vector3(-20.0, -22.0, -20.0), Vector3(40.0, 44.0, 40.0))
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(width, length)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Do not apply a second billboard transform in the material: it can
	# interfere with the particle system's upright mesh orientation.
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_color = Color(rain_color.r, rain_color.g, rain_color.b, alpha)
	material.albedo_texture = _drop_texture
	mesh.material = material
	layer.draw_pass_1 = mesh
	# Screen-facing quads with their LONG (local Y) dimension upright.
	# This gives vertical streaks even when the camera is angled over the shore.
	layer.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	var processing: ParticleProcessMaterial = ParticleProcessMaterial.new()
	processing.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	processing.emission_box_extents = Vector3(visible_width * 0.5 * spread_scale, 0.5, visible_depth * 0.5 * spread_scale)
	processing.direction = Vector3.DOWN
	processing.spread = 3.0
	processing.angle_min = 0.0
	processing.angle_max = 0.0
	processing.angular_velocity_min = 0.0
	processing.angular_velocity_max = 0.0
	processing.gravity = Vector3(0.0, -9.8, 0.0)
	processing.initial_velocity_min = 5.0
	processing.initial_velocity_max = 7.0
	layer.process_material = processing
	add_child(layer)
	return layer

func _apply_wind_drift() -> void:
	# Wind bends the rain slightly; it never controls whether rain is active.
	var service: Node = get_tree().root.get_node_or_null("GameWind")
	var drift: Vector2 = Vector2.ZERO
	if service != null and service.has_method("get_snapshot"):
		var state: Dictionary = service.call("get_snapshot") as Dictionary
		if bool(state.get("available", false)):
			drift = state.get("velocity_xz", Vector2.ZERO) as Vector2
	for rain in [_rain_particles, _distant_rain_particles]:
		if rain == null:
			continue
		var processing: ParticleProcessMaterial = rain.process_material as ParticleProcessMaterial
		if processing != null:
			processing.direction = Vector3(drift.x * 0.055, -1.0, drift.y * 0.055).normalized()
			processing.gravity = Vector3(drift.x * 0.32, -9.8, drift.y * 0.32)

func _build_splash_frames() -> void:
	_splash_frames = SpriteFrames.new()
	# Keep both animation names so existing ground/water callers still work,
	# but ALWAYS select the same small five frames in the TOP sprite row.
	# Nothing from y=32 onward is ever sampled or displayed.
	for name in [&"ground", &"water"]:
		_splash_frames.add_animation(name)
		_splash_frames.set_animation_speed(name, splash_fps)
		_splash_frames.set_animation_loop(name, false)
		for index in range(5):
			var cell: AtlasTexture = AtlasTexture.new()
			cell.atlas = SPLASH_ATLAS
			cell.region = Rect2(4 + 19 * index, 3, 18, 19)
			_splash_frames.add_frame(name, cell)

func _follow_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _rain_particles == null:
		return
	var forward: Vector3 = -camera.global_basis.z
	var focus: Vector3 = camera.global_position + forward * camera_focus_distance
	var origin: Vector3 = Vector3(focus.x, camera.global_position.y + spawn_height_above_camera, focus.z)
	# Emit near the active view, not over a vast world-space box. Combined
	# with tiny droplet meshes, this gives many small streaks in view.
	_rain_particles.global_position = origin
	if _distant_rain_particles != null:
		_distant_rain_particles.global_position = origin + Vector3(0.0, 0.6, 0.0)

func _spawn_impact() -> void:
	if _splashes.size() >= max_simultaneous_splashes:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var sea: MeshInstance3D = _find_sea()
	var sea_y: float = sea.global_position.y if sea != null else 0.0
	for attempt in range(7):
		var screen_point: Vector2 = Vector2(
			_rng.randf_range(0.12, 0.88) * viewport_size.x,
			_rng.randf_range(0.24, 0.86) * viewport_size.y
		)
		var ray_origin: Vector3 = camera.project_ray_origin(screen_point)
		var ray_direction: Vector3 = camera.project_ray_normal(screen_point)
		if absf(ray_direction.y) < 0.01:
			continue
		var distance: float = (sea_y - ray_origin.y) / ray_direction.y
		if distance <= 0.0 or distance > 300.0:
			continue
		var point: Vector3 = ray_origin + ray_direction * distance
		var on_water: bool = _within_sea(point, sea)
		if not on_water:
			var ground: Vector3 = _ground_intersection(ray_origin, ray_direction)
			if ground.x == INF:
				continue
			point = ground
		_spawn_splash(point + Vector3.UP * 0.035, &"water" if on_water else &"ground")
		return

func _ground_intersection(origin: Vector3, direction: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + direction * 200.0)
	query.collision_mask = 0xFFFFFFFF
	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty():
		return result["position"] as Vector3
	# Some authored shore geometry is decorative and has no collider.
	# Only use a height-plane fallback when the intersection lies inside
	# the actual beach mesh footprint. Never make an impact in empty void.
	if not is_instance_valid(_beach):
		_beach = get_node_or_null("../beach/Beach") as MeshInstance3D
	if _beach == null or _beach.mesh == null or absf(direction.y) < 0.01:
		return Vector3(INF, INF, INF)
	var target_y: float = _beach.global_position.y + 0.025
	var travel: float = (target_y - origin.y) / direction.y
	if travel <= 0.0 or travel > 200.0:
		return Vector3(INF, INF, INF)
	var point: Vector3 = origin + direction * travel
	var local: Vector3 = _beach.to_local(point)
	var bounds: AABB = _beach.get_aabb()
	if local.x >= bounds.position.x and local.x <= bounds.end.x and local.z >= bounds.position.z and local.z <= bounds.end.z:
		return point
	return Vector3(INF, INF, INF)

func _find_sea() -> MeshInstance3D:
	if not is_instance_valid(_sea):
		_sea = get_node_or_null("../beach/Sea") as MeshInstance3D
	return _sea

func _within_sea(point: Vector3, sea: MeshInstance3D) -> bool:
	if sea == null or sea.mesh == null:
		return false
	var local: Vector3 = sea.to_local(point)
	var bounds: AABB = sea.get_aabb()
	return local.x >= bounds.position.x and local.x <= bounds.end.x and local.z >= bounds.position.z and local.z <= bounds.end.z

func _spawn_splash(at_position: Vector3, animation: StringName) -> void:
	if _splashes.size() >= max_simultaneous_splashes:
		return
	var sprite: AnimatedSprite3D
	if _splash_pool.is_empty():
		sprite = AnimatedSprite3D.new()
		sprite.name = "RainSplash"
		sprite.sprite_frames = _splash_frames
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sprite.rotation_degrees.x = -90.0 # Ripple lies on the ground/water plane.
		sprite.double_sided = true
		sprite.shaded = false
		sprite.no_depth_test = false
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		sprite.animation_finished.connect(_recycle_splash.bind(sprite))
	else:
		sprite = _splash_pool.pop_back()
	sprite.pixel_size = splash_pixel_size
	sprite.modulate = Color(
		splash_color.r, splash_color.g, splash_color.b,
		clampf(splash_color.a * splash_opacity, 0.0, 1.0)
	)
	sprite.global_position = at_position
	sprite.visible = true
	_splashes.append(sprite)
	sprite.play(animation)

func _recycle_splash(sprite: AnimatedSprite3D) -> void:
	if not is_instance_valid(sprite):
		return
	sprite.stop()
	sprite.visible = false
	_splashes.erase(sprite)
	_splash_pool.append(sprite)

func is_raining() -> bool:
	return _raining

func get_active_splash_count() -> int:
	var count: int = 0
	for splash in _splashes:
		if is_instance_valid(splash):
			count += 1
	return count
