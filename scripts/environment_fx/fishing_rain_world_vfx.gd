extends Node3D
## Ambient rain is world-owned, independent of casting or fishing mode.
## Rain and water/ground impact visuals are presentation only.
## Rainfall is emitted ABOVE the camera frame and moves completely through it.
## Screen-space speed and size remain stable when plane distance changes. It remains 3D,
## behind the 2D game UI; splashes continue to live on real world surfaces.
## All surface impacts use ONLY the small five-frame TOP ROW of RainImpact.png.

const SPLASH_ATLAS: Texture2D = preload("res://assets/ui/environment/RainImpact.png")
const POLL_SECONDS: float = 0.5
const WeatherPresentationPolicy = preload("res://scripts/environment_fx/environment_weather_presentation_policy.gd")

@export_category("Rain Mode")
@export_enum("Auto", "Clear", "Rain Preview", "Storm Preview") var weather_mode: int = 0
@export var enabled: bool = true

@export_category("Rainfall - Camera-Filling")
@export_range(24, 600, 1) var drop_count: int = 220
@export_range(0.002, 0.04, 0.001) var drop_width: float = 0.010
@export_range(0.025, 0.28, 0.005) var drop_length: float = 0.095
@export_range(0.0, 1.0, 0.01) var drop_opacity: float = 1.0
@export var rain_color: Color = Color("#D3ECFF")
## The dark rim shares the SAME overall opacity as the bright center.
@export_range(0.0, 0.6, 0.01) var drop_edge_opacity: float = 0.27
## Emitter follows the camera frustum, rather than a world-space box.
@export_range(1.0, 1.6, 0.05) var screen_coverage: float = 1.10
## Rendering depth only; does NOT alter the perceived fall speed or streak length.
@export_range(1.0, 4.0, 0.25) var rain_plane_distance: float = 2.0
## Viewport-heights per second: independent of length, width and plane distance.
@export_range(0.25, 6.0, 0.05) var drop_fall_speed: float = 2.1
@export_range(-50.0, 50.0, 1.0) var drop_angle_degrees: float = 0.0
@export var follow_wind_direction: bool = false
@export_range(0.0, 3.0, 0.05) var wind_angle_influence: float = 1.0
@export_range(0.1, 0.9, 0.05) var distant_rain_share: float = 0.30

@export_category("Weather Transitions - Visual Only")
## Transitions smooth the particles and ripple spawn rate; gameplay weather
## remains authoritative and changes immediately at its scheduled boundary.
@export_range(0.0, 15.0, 0.1) var rain_fade_in_seconds: float = 2.5
@export_range(0.0, 15.0, 0.1) var rain_fade_out_seconds: float = 4.0
@export_range(0.0, 15.0, 0.1) var storm_transition_seconds: float = 3.0

@export_category("Surface Ripples - Top Row Only")
@export_range(0.001, 0.04, 0.001) var splash_pixel_size: float = 0.003
@export_range(1.0, 30.0, 1.0) var splash_fps: float = 12.0
@export_range(1.0, 300.0, 1.0) var splash_rate_per_second: float = 80.0
@export_range(1, 250, 1) var max_simultaneous_splashes: int = 100
## Balance water/ground impacts when both surfaces are on screen.
@export_range(0.0, 1.0, 0.05) var water_splash_share: float = 0.65
@export var splash_color: Color = Color("#8E9DC4AB")
@export_range(0.0, 1.0, 0.01) var splash_opacity: float = 0.38

var _weather_timer: float = 0.0
var _impact_timer: float = 0.0
var _raining: bool = false
var _storm: bool = false
var _weather_initialized: bool = false
var _target_rain_level: float = 0.0
var _target_storm_level: float = 0.0
var _rain_level: float = 0.0
var _storm_level: float = 0.0
var _rain_particles: GPUParticles3D = null
var _distant_rain_particles: GPUParticles3D = null
var _last_rain_appearance: Array = []
var _last_rain_amounts: Vector2i = Vector2i(-1, -1)
var _drop_texture: Texture2D = null
var _beach: MeshInstance3D = null
var _sea: MeshInstance3D = null
var _sea_triangles: Array[PackedVector3Array] = []
var _beach_triangles: Array[PackedVector3Array] = []
var _last_splash_appearance: Array = []
var _splash_frames: SpriteFrames = null
var _splashes: Array[AnimatedSprite3D] = []
var _splash_pool: Array[AnimatedSprite3D] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_create_rainfall()
	_build_splash_frames()
	_follow_camera()
	_poll_weather()
	set_process(true)

func _process(delta: float) -> void:
	_weather_timer += delta
	if _weather_timer >= POLL_SECONDS:
		_weather_timer = 0.0
		_poll_weather()
	# Gameplay weather changes immediately; only the presentation blends.
	# The approved appearance remains identical once a normal rain settles.
	_update_visual_weather(delta)
	# Inspector edits also affect running previews; no restart needed for rain
	# color, opacity, number, size or fall speed.
	_sync_rain_appearance()
	_sync_splash_appearance()
	if _rain_level <= 0.001:
		_impact_timer = 0.0
		return
	_follow_camera()
	# Ripples slow down with the outgoing rain instead of suddenly stopping.
	# A settled storm retains its original 1.3x impact-rate behavior.
	var rate: float = maxf(1.0, splash_rate_per_second) * WeatherPresentationPolicy.splash_rate_factor(_rain_level, _storm_level)
	if rate <= 0.01:
		_impact_timer = 0.0
		return
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

func _weather_tags() -> PackedStringArray:
	# The active gameplay environment takes precedence, including the
	# intentional manual preview override from Environmental Integration v1.
	var game: Node = get_parent().get_parent() if get_parent() != null and get_parent().get_parent() != null else null
	var fishing: Node = game.get_node_or_null("Game/Fishing") if game != null else null
	if fishing != null:
		var environment: Node = fishing.get("fishing_environment_service") as Node
		if is_instance_valid(environment) and environment.has_method("get_active_tags"):
			var gameplay_tags: PackedStringArray = environment.call("get_active_tags") as PackedStringArray
			if not gameplay_tags.is_empty():
				# The fishing session can exist before the deferred global weather
				# provider does. Ignore its provisional Calm default until the
				# live service actually has a weather source. Real manual/detached
				# services and injected QA providers keep their previous behavior.
				var waiting_for_live_source: bool = (
					environment.has_method("enable_live_weather")
					and bool(environment.get("_live_weather_enabled"))
					and not is_instance_valid(environment.get("_weather_source"))
				)
				if not waiting_for_live_source:
					return gameplay_tags
	# World effects may be active while the fishing controller isn't mounted
	# (travel, initialization, stand-alone locations). Read the same world
	# weather provider; never create a second weather simulation here.
	# Detached scene fixtures are legitimate: get_tree() itself logs an
	# engine error when called outside a SceneTree. Check first.
	if is_inside_tree():
		var weather: Node = get_tree().root.get_node_or_null("GameWeather")
		if is_instance_valid(weather) and weather.has_method("get_snapshot"):
			var snapshot: Dictionary = weather.call("get_snapshot") as Dictionary
			if bool(snapshot.get("available", false)):
				return snapshot.get("tags", PackedStringArray()) as PackedStringArray
	return PackedStringArray()


func _poll_weather() -> void:
	var tags: PackedStringArray = _weather_tags()
	# The location can enter the tree before WorldLocations finishes its deferred
	# GameClock/GameWeather mount. Do not mistake that temporary absence of a
	# provider for an authored Clear condition: a location joined during Rain or
	# Tempest should start at the current intensity, not replay a fade-in.
	# Explicit Inspector preview modes still initialize immediately.
	if not _weather_initialized and weather_mode == 0 and tags.is_empty():
		return
	var state: String = _resolve_weather(tags)
	_raining = state != "clear"
	_storm = state == "storm"
	var target: Vector2 = WeatherPresentationPolicy.target_levels(state)
	_target_rain_level = target.x
	_target_storm_level = target.y
	if not _weather_initialized:
		# Joining an already-raining location should NOT replay the fade-in.
		_rain_level = _target_rain_level
		_storm_level = _target_storm_level
		_weather_initialized = true
	_update_emission_state()


func _update_visual_weather(delta: float) -> void:
	_rain_level = WeatherPresentationPolicy.step_level(
		_rain_level, _target_rain_level, delta,
		rain_fade_in_seconds, rain_fade_out_seconds
	)
	_storm_level = WeatherPresentationPolicy.step_level(
		_storm_level, _target_storm_level, delta,
		storm_transition_seconds, storm_transition_seconds
	)
	_update_emission_state()


func _update_emission_state() -> void:
	var should_emit: bool = WeatherPresentationPolicy.should_emit(_rain_level, _target_rain_level)
	if _rain_particles != null and _rain_particles.emitting != should_emit:
		_rain_particles.emitting = should_emit
	if _distant_rain_particles != null and _distant_rain_particles.emitting != should_emit:
		_distant_rain_particles.emitting = should_emit

func _create_rainfall() -> void:
	_drop_texture = _create_drop_texture()
	_rain_particles = _make_rain_layer(&"NearRain", 1.0)
	_distant_rain_particles = _make_rain_layer(&"DistantRain", 1.6)
	_sync_rain_appearance()

func _create_drop_texture() -> Texture2D:
	# A tapered pixel-art silhouette, separate from RainImpact.png.
	var picture: Image = Image.create(5, 15, false, Image.FORMAT_RGBA8)
	for y in range(15):
		var progress: float = float(y) / 14.0
		var taper: float = pow(sin(PI * progress), 1.15)
		for x in range(5):
			var center_weight: float = 1.0 if x == 2 else (0.42 if x == 1 or x == 3 else 0.0)
			picture.set_pixel(x, y, Color(1.0, 1.0, 1.0, taper * center_weight))
	return ImageTexture.create_from_image(picture)

func _make_streak_mesh(width: float, length: float, color: Color) -> QuadMesh:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(width, length)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_color = color
	material.albedo_texture = _drop_texture
	mesh.material = material
	return mesh

func _make_rain_layer(layer_name: StringName, depth_scale: float) -> GPUParticles3D:
	var layer: GPUParticles3D = GPUParticles3D.new()
	layer.name = String(layer_name)
	layer.amount = 1 # _sync_rain_appearance assigns the requested budget.
	layer.lifetime = 0.70 # Updated from the viewport-height/speed relationship.
	layer.preprocess = 0.70 # Fill the whole screen immediately on rain start.
	layer.explosiveness = 0.0
	layer.randomness = 0.0
	# LOCAL coordinates are essential: the emitter planes travel with the
	# camera, keeping already-living rain over the visible picture.
	layer.local_coords = true
	layer.emitting = false
	layer.visibility_aabb = AABB(Vector3(-40, -40, -4), Vector3(80, 80, 8))
	# Quads face the camera because the entire emitter follows its basis.
	# No GPU billboard transform can twist a vertical line sideways.
	layer.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	layer.draw_passes = 2
	layer.draw_pass_1 = _make_streak_mesh(
		drop_width * 1.8, drop_length * 1.05,
		Color(0.09, 0.17, 0.28, drop_edge_opacity)
	)
	layer.draw_pass_2 = _make_streak_mesh(drop_width, drop_length, rain_color)
	var processing: ParticleProcessMaterial = ParticleProcessMaterial.new()
	processing.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	processing.emission_box_extents = Vector3(1.0, 0.002, 0.015 * depth_scale)
	# Spawn in a thin row ABOVE the top of the picture, then fall THROUGH
	# the whole viewport. Rotation of the entire layer adds the wind slant.
	processing.direction = Vector3.DOWN
	processing.spread = 0.0
	processing.angle_min = 0.0
	processing.angle_max = 0.0
	processing.angular_velocity_min = 0.0
	processing.angular_velocity_max = 0.0
	processing.gravity = Vector3.ZERO
	processing.initial_velocity_min = 1.0 # Set per camera frustum below.
	processing.initial_velocity_max = 1.1
	layer.process_material = processing
	add_child(layer)
	return layer

func _sync_rain_appearance() -> void:
	if _rain_particles == null or _distant_rain_particles == null:
		return
	var distant_count: int = maxi(1, roundi(float(drop_count) * distant_rain_share))
	var near_count: int = maxi(1, drop_count - distant_count)
	var counts: Vector2i = Vector2i(near_count, distant_count)
	if counts != _last_rain_amounts:
		_rain_particles.amount = near_count
		_distant_rain_particles.amount = distant_count
		_last_rain_amounts = counts
	var settings: Array = [drop_width, drop_length, drop_opacity, rain_color,
		drop_edge_opacity, drop_fall_speed, drop_angle_degrees,
		snappedf(_rain_level, 0.01)]
	if settings == _last_rain_appearance:
		return
	_last_rain_appearance = settings.duplicate()
	for layer in [_rain_particles, _distant_rain_particles]:
		var distant: bool = layer == _distant_rain_particles
		var scale_factor: float = 0.72 if distant else 1.0
		var alpha_factor: float = 0.72 if distant else 1.0
		var shadow: QuadMesh = layer.draw_pass_1 as QuadMesh
		var highlight: QuadMesh = layer.draw_pass_2 as QuadMesh
		shadow.size = Vector2(drop_width * scale_factor * 1.8, drop_length * scale_factor * 1.05)
		highlight.size = Vector2(drop_width * scale_factor, drop_length * scale_factor)
		var shadow_material: StandardMaterial3D = shadow.material as StandardMaterial3D
		var highlight_material: StandardMaterial3D = highlight.material as StandardMaterial3D
		var final_alpha: float = clampf(rain_color.a * drop_opacity * alpha_factor * _rain_level, 0.0, 1.0)
		shadow_material.albedo_color = Color(0.09, 0.17, 0.28,
			clampf(drop_edge_opacity * final_alpha, 0.0, 1.0))
		highlight_material.albedo_color = Color(rain_color.r, rain_color.g,
			rain_color.b, final_alpha)


func _effective_drop_angle(camera: Camera3D) -> float:
	var angle: float = drop_angle_degrees
	if follow_wind_direction and camera != null:
		var wind: Node = get_tree().root.get_node_or_null("GameWind")
		if wind != null and wind.has_method("get_snapshot"):
			var snapshot: Dictionary = wind.call("get_snapshot") as Dictionary
			if bool(snapshot.get("available", false)):
				var drift: Vector2 = snapshot.get("velocity_xz", Vector2.ZERO)
				var rightward: float = Vector3(drift.x, 0.0, drift.y).dot(camera.global_basis.x)
				angle += rightward * 5.0 * wind_angle_influence
	return clampf(angle, -50.0, 50.0)

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
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x < 2.0 or viewport_size.y < 2.0:
		return
	var basis: Basis = camera.global_transform.basis.orthonormalized()
	var angle_radians: float = deg_to_rad(_effective_drop_angle(camera))
	var rotation: Basis = Basis(Vector3.BACK, angle_radians)
	# Positive angles mean rain moves to the right as it falls.
	# The emitter is centered upstream to make both shoreline and open sea
	# receive the same on-screen density, even during angled winds.
	var top_x: float = viewport_size.x * 0.5 - tan(angle_radians) * viewport_size.y * 0.52
	var top_screen: Vector2 = Vector2(top_x, -viewport_size.y * 0.10)
	var ref_top: Vector3 = camera.project_position(Vector2(viewport_size.x * 0.5, 0.0), 2.0)
	var ref_bottom: Vector3 = camera.project_position(Vector2(viewport_size.x * 0.5, viewport_size.y), 2.0)
	var ref_height: float = maxf(ref_top.distance_to(ref_bottom), 0.001)
	for layer in [_rain_particles, _distant_rain_particles]:
		var distant: bool = layer == _distant_rain_particles
		var distance: float = rain_plane_distance * (1.55 if distant else 1.0)
		var top_left: Vector3 = camera.project_position(Vector2.ZERO, distance)
		var top_right: Vector3 = camera.project_position(Vector2(viewport_size.x, 0.0), distance)
		var bottom_left: Vector3 = camera.project_position(Vector2(0.0, viewport_size.y), distance)
		var screen_width: float = top_left.distance_to(top_right)
		var screen_height: float = top_left.distance_to(bottom_left)
		layer.global_transform = Transform3D(basis * rotation, camera.project_position(top_screen, distance))
		var process_material: ParticleProcessMaterial = layer.process_material as ParticleProcessMaterial
		var angled_width: float = screen_width + absf(tan(angle_radians)) * screen_height * 1.15
		var volume: Vector3 = Vector3(angled_width * screen_coverage * 0.5, 0.002, 0.015)
		if not process_material.emission_box_extents.is_equal_approx(volume):
			process_material.emission_box_extents = volume
		# World distance, mesh size and camera FOV no longer determine visual
		# speed: always move the same share of the picture per second.
		var speed_world: float = screen_height * drop_fall_speed / maxf(cos(angle_radians), 0.55)
		var speed_min: float = speed_world * 0.94
		var speed_max: float = speed_world * 1.06
		# Raise max before min when accelerating; lower min before max
		# when decelerating, so range constraints never clamp the new speed.
		if speed_max > process_material.initial_velocity_max:
			process_material.initial_velocity_max = speed_max
		if not is_equal_approx(process_material.initial_velocity_min, speed_min):
			process_material.initial_velocity_min = speed_min
		if not is_equal_approx(process_material.initial_velocity_max, speed_max):
			process_material.initial_velocity_max = speed_max
		var travel_lifetime: float = 1.4 / maxf(drop_fall_speed, 0.25)
		if absf(layer.lifetime - travel_lifetime) > 0.002:
			layer.lifetime = travel_lifetime
			layer.preprocess = travel_lifetime
		# Width and length are evaluated at a constant reference depth, so
		# increasing Rain Plane Distance never makes drops 'slower' or larger.
		var view_scale: float = screen_height / ref_height
		var depth_scale: float = 0.72 if distant else 1.0
		var rim: QuadMesh = layer.draw_pass_1 as QuadMesh
		var core: QuadMesh = layer.draw_pass_2 as QuadMesh
		var rim_size: Vector2 = Vector2(drop_width * 1.8, drop_length * 1.05) * view_scale * depth_scale
		var core_size: Vector2 = Vector2(drop_width, drop_length) * view_scale * depth_scale
		if not rim.size.is_equal_approx(rim_size):
			rim.size = rim_size
		if not core.size.is_equal_approx(core_size):
			core.size = core_size

func _find_sea() -> MeshInstance3D:
	if not is_instance_valid(_sea):
		_sea = get_node_or_null("../beach/Sea") as MeshInstance3D
		_sea_triangles.clear()
	return _sea

func _find_beach() -> MeshInstance3D:
	if not is_instance_valid(_beach):
		_beach = get_node_or_null("../beach/Beach") as MeshInstance3D
		_beach_triangles.clear()
	return _beach

func _mesh_triangles(mesh_node: MeshInstance3D, water: bool) -> Array[PackedVector3Array]:
	# The original GLB uses an uneven/sloped Sea mesh. Test its real
	# triangles rather than intersecting an invented horizontal Y-plane.
	if water and not _sea_triangles.is_empty():
		return _sea_triangles
	if not water and not _beach_triangles.is_empty():
		return _beach_triangles
	var triangles: Array[PackedVector3Array] = []
	if mesh_node == null or mesh_node.mesh == null:
		return triangles
	var array_mesh: ArrayMesh = mesh_node.mesh as ArrayMesh
	for surface in range(mesh_node.mesh.get_surface_count()):
		if array_mesh != null and array_mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.size() > 0:
			for i in range(0, indices.size() - 2, 3):
				triangles.append(PackedVector3Array([
					vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]]
				]))
		else:
			for i in range(0, vertices.size() - 2, 3):
				triangles.append(PackedVector3Array([vertices[i], vertices[i + 1], vertices[i + 2]]))
	if water:
		_sea_triangles = triangles
	else:
		_beach_triangles = triangles
	return triangles

func _mesh_ray_hit(origin: Vector3, direction: Vector3, mesh_node: MeshInstance3D, water: bool) -> Vector3:
	if mesh_node == null or mesh_node.mesh == null:
		return Vector3.INF
	var source: Vector3 = mesh_node.to_local(origin)
	var vector: Vector3 = mesh_node.to_local(origin + direction) - source
	var closest: float = INF
	var result: Vector3 = Vector3.INF
	for face in _mesh_triangles(mesh_node, water):
		var edge_a: Vector3 = face[1] - face[0]
		var edge_b: Vector3 = face[2] - face[0]
		var cross_a: Vector3 = vector.cross(edge_b)
		var determinant: float = edge_a.dot(cross_a)
		if absf(determinant) < 0.0000001:
			continue
		var inverse: float = 1.0 / determinant
		var offset: Vector3 = source - face[0]
		var u: float = inverse * offset.dot(cross_a)
		if u < -0.00001 or u > 1.00001:
			continue
		var cross_b: Vector3 = offset.cross(edge_a)
		var v: float = inverse * vector.dot(cross_b)
		if v < -0.00001 or u + v > 1.00001:
			continue
		var travel: float = inverse * edge_b.dot(cross_b)
		if travel > 0.0001 and travel < closest:
			closest = travel
			result = mesh_node.to_global(source + vector * travel)
	return result

func _spawn_impact() -> void:
	if _splashes.size() >= max_simultaneous_splashes:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x < 2.0 or viewport_size.y < 2.0:
		return
	var sea: MeshInstance3D = _find_sea()
	var beach: MeshInstance3D = _find_beach()
	var want_water: bool = _rng.randf() < water_splash_share
	var fallback: Vector3 = Vector3.INF
	var fallback_is_water: bool = false
	# Sample the picture rather than arbitrary world coordinates. Prioritize
	# both materials when visible so water ripples aren't lost in the sand.
	for attempt in range(16):
		var screen_point: Vector2 = Vector2(
			_rng.randf_range(0.04, 0.96) * viewport_size.x,
			_rng.randf_range(0.06, 0.95) * viewport_size.y
		)
		var origin: Vector3 = camera.project_ray_origin(screen_point)
		var direction: Vector3 = camera.project_ray_normal(screen_point)
		var on_sea: Vector3 = _mesh_ray_hit(origin, direction, sea, true)
		var on_beach: Vector3 = _mesh_ray_hit(origin, direction, beach, false)
		var water: bool = on_sea.x != INF and (
			on_beach.x == INF or origin.distance_squared_to(on_sea) < origin.distance_squared_to(on_beach)
		)
		var hit: Vector3 = on_sea if water else on_beach
		if hit.x == INF:
			continue
		if fallback.x == INF:
			fallback = hit
			fallback_is_water = water
		if water == want_water:
			_spawn_splash(hit + Vector3.UP * 0.012, &"water" if water else &"ground")
			return
	if fallback.x != INF:
		_spawn_splash(fallback + Vector3.UP * 0.012, &"water" if fallback_is_water else &"ground")

func _ground_intersection(origin: Vector3, direction: Vector3) -> Vector3:
	# Kept for existing QA/external callers. Surface lookup uses the real
	# authored Beach mesh rather than a generic collision hit (which might
	# accidentally be an underwater floor or NPC collider).
	return _mesh_ray_hit(origin, direction, _find_beach(), false)

func _sync_splash_appearance() -> void:
	var settings: Array = [splash_color, splash_opacity, splash_pixel_size, splash_fps]
	if settings == _last_splash_appearance:
		return
	_last_splash_appearance = settings.duplicate()
	if _splash_frames != null:
		for name in [&"ground", &"water"]:
			_splash_frames.set_animation_speed(name, splash_fps)
	for sprite in _splashes:
		if is_instance_valid(sprite):
			_apply_splash_style(sprite)

func _apply_splash_style(sprite: AnimatedSprite3D) -> void:
	sprite.pixel_size = splash_pixel_size
	sprite.modulate = Color(
		splash_color.r, splash_color.g, splash_color.b,
		clampf(splash_color.a * splash_opacity, 0.0, 1.0)
	)

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
	_apply_splash_style(sprite)
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
