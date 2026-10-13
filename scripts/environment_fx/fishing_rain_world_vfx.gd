extends Node3D
## Ambient rain is world-owned, independent of casting or fishing mode.
## Rain and water/ground impact visuals are presentation only.

const SPLASH_ATLAS: Texture2D = preload("res://assets/ui/environment/RainImpact.png")
const POLL_SECONDS: float = 0.5

@export_category("Rain Mode")
@export_enum("Auto", "Clear", "Rain Preview", "Storm Preview") var weather_mode: int = 0
@export var enabled: bool = true

@export_category("Rainfall")
@export_range(12, 240, 1) var drop_count: int = 85
@export_range(0.005, 0.08, 0.005) var drop_width: float = 0.018
@export_range(0.05, 0.8, 0.05) var drop_length: float = 0.27
@export_range(0.05, 1.0, 0.05) var drop_opacity: float = 0.38
@export_range(2.0, 24.0, 0.5) var visible_width: float = 11.0
@export_range(2.0, 24.0, 0.5) var visible_depth: float = 10.0

@export_category("Occasional Big Drops")
@export_range(0.15, 3.0, 0.05) var impact_interval: float = 0.7
@export_range(0.005, 0.08, 0.005) var splash_pixel_size: float = 0.018
@export_range(1.0, 30.0, 1.0) var splash_fps: float = 12.0
@export_range(1, 25, 1) var max_simultaneous_splashes: int = 9

var _weather_timer: float = 0.0
var _impact_timer: float = 0.0
var _raining: bool = false
var _storm: bool = false
var _rain_particles: GPUParticles3D = null
var _sea: MeshInstance3D = null
var _player: Node3D = null
var _splash_frames: SpriteFrames = null
var _splashes: Array[AnimatedSprite3D] = []
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
	_impact_timer += delta
	var interval: float = impact_interval * (0.55 if _storm else 1.0)
	if _impact_timer >= interval:
		_impact_timer = 0.0
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

func _create_rainfall() -> void:
	_rain_particles = GPUParticles3D.new()
	_rain_particles.name = "AmbientRain"
	_rain_particles.amount = drop_count
	_rain_particles.lifetime = 1.6
	_rain_particles.explosiveness = 0.0
	_rain_particles.randomness = 0.25
	_rain_particles.local_coords = false
	_rain_particles.emitting = false
	_rain_particles.visibility_aabb = AABB(Vector3(-25.0, -16.0, -25.0), Vector3(50.0, 36.0, 50.0))
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(drop_width, drop_length)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(0.78, 0.88, 0.98, drop_opacity)
	material.vertex_color_use_as_albedo = false
	mesh.material = material
	_rain_particles.draw_pass_1 = mesh
	var process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(visible_width * 0.5, 0.4, visible_depth * 0.5)
	process_material.direction = Vector3.DOWN
	process_material.spread = 4.0
	process_material.gravity = Vector3(0.0, -11.0, 0.0)
	process_material.initial_velocity_min = 6.0
	process_material.initial_velocity_max = 8.0
	_rain_particles.process_material = process_material
	add_child(_rain_particles)

func _build_splash_frames() -> void:
	_splash_frames = SpriteFrames.new()
	for name in [&"ground", &"water"]:
		_splash_frames.add_animation(name)
		_splash_frames.set_animation_speed(name, splash_fps)
		_splash_frames.set_animation_loop(name, false)
		var count: int = 5
		for index in range(count):
			var cell: AtlasTexture = AtlasTexture.new()
			cell.atlas = SPLASH_ATLAS
			if name == &"ground":
				cell.region = Rect2(4 + 19 * index, 3, 18, 19)
			else:
				cell.region = Rect2(4 + 27 * index, 32, 26, 30)
			_splash_frames.add_frame(name, cell)

func _follow_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _rain_particles == null:
		return
	var forward: Vector3 = -camera.global_basis.z
	var focus: Vector3 = camera.global_position + forward * 7.0
	# Each update is smooth; existing particles remain in world space.
	_rain_particles.global_position = Vector3(focus.x, camera.global_position.y + 7.0, focus.z)

func _spawn_impact() -> void:
	for i in range(_splashes.size() - 1, -1, -1):
		if not is_instance_valid(_splashes[i]):
			_splashes.remove_at(i)
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
	if not is_instance_valid(_player):
		_player = get_node_or_null("../../Player/CharacterBody3D") as Node3D
	var ground_y: float = _player.global_position.y if _player != null else 0.0
	if absf(direction.y) > 0.01:
		var distance: float = (ground_y - origin.y) / direction.y
		if distance > 0.0:
			return origin + direction * distance
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
	var sprite: AnimatedSprite3D = AnimatedSprite3D.new()
	sprite.name = "RainSplash"
	sprite.sprite_frames = _splash_frames
	sprite.pixel_size = splash_pixel_size
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.rotation_degrees.x = -90.0 # Splashes lie ON the ground/water plane.
	sprite.double_sided = true
	sprite.shaded = false
	sprite.no_depth_test = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	sprite.global_position = at_position
	_splashes.append(sprite)
	sprite.animation_finished.connect(sprite.queue_free)
	sprite.play(animation)

func is_raining() -> bool:
	return _raining

func get_active_splash_count() -> int:
	var count: int = 0
	for splash in _splashes:
		if is_instance_valid(splash):
			count += 1
	return count
