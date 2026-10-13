extends SceneTree
## Rain visual regression: full-height rain, sea-mesh impacts, opacity and top-row ripples.
## Run with --headless --path . --script res://scripts/qa/environment_rain_visual_v3_qa.gd

const RainScene: PackedScene = preload("res://actors/FishingRainVFX.tscn")
const ImpactAtlas: Texture2D = preload("res://assets/ui/environment/RainImpact.png")

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("RAIN V3 QA: " + description)

func run() -> void:
	var host: Node3D = Node3D.new()
	host.name = "RainVisualTestHost"
	root.add_child(host)
	var camera: Camera3D = Camera3D.new()
	camera.name = "TestCamera"
	camera.position = Vector3(0.0, 4.0, 7.0)
	host.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.make_current()
	var world: Node3D = Node3D.new()
	world.name = "World"
	host.add_child(world)
	var rain: Node3D = RainScene.instantiate() as Node3D
	world.add_child(rain)
	verify(rain != null, "Rain scene instantiates")
	if rain == null:
		finish()
		return
	var near: GPUParticles3D = rain.get_node_or_null("NearRain") as GPUParticles3D
	var far: GPUParticles3D = rain.get_node_or_null("DistantRain") as GPUParticles3D
	verify(near != null and far != null, "near and distant rain layers exist")
	if near != null and far != null:
		verify(near.amount + far.amount == int(rain.get("drop_count")), "particle count is divided between layers")
		verify(near.local_coords and far.local_coords, "rain follows moving camera without leaving gaps")
		verify(near.transform_align == GPUParticles3D.TRANSFORM_ALIGN_DISABLED, "near rain is not independently billboard-rotated")
		verify(far.transform_align == GPUParticles3D.TRANSFORM_ALIGN_DISABLED, "far rain is not independently billboard-rotated")
		verify(near.draw_passes == 2 and far.draw_passes == 2, "rain has outline and bright streak passes")
		var near_mesh: QuadMesh = near.draw_pass_2 as QuadMesh
		var far_mesh: QuadMesh = far.draw_pass_2 as QuadMesh
		verify(near_mesh != null and far_mesh != null, "bright rain quads exist")
		if near_mesh != null and far_mesh != null:
			verify(near_mesh.size.y < 0.14 and near_mesh.size.x < 0.02, "near rain lines stay tiny")
			verify(far_mesh.size.y < near_mesh.size.y, "far rain lines stay shorter")
			var near_material: StandardMaterial3D = near_mesh.material as StandardMaterial3D
			verify(near_material != null, "near rain uses a material")
			if near_material != null:
				verify(near_material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED, "no competing billboard rotation")
				verify(near_material.no_depth_test, "rain remains visible over background scene geometry")
				verify(near_material.albedo_texture != null, "tapered rain texture is loaded")
				verify(near_material.albedo_color.b > near_material.albedo_color.r, "rain highlight is light blue")
				verify(is_equal_approx(near_material.albedo_color.a, 0.7), "user-set drop opacity is honored")
			var shadow_mesh: QuadMesh = near.draw_pass_1 as QuadMesh
			verify(shadow_mesh != null and shadow_mesh.size.x > near_mesh.size.x, "dark contrast edge surrounds highlight")
		var near_processing: ParticleProcessMaterial = near.process_material as ParticleProcessMaterial
		verify(near_processing.direction.y < -0.9, "particle fall direction is locally vertical")
	verify(ImpactAtlas.get_width() == 142 and ImpactAtlas.get_height() == 66, "original impact sheet preserved, only top row referenced")
	verify(is_equal_approx(float(rain.get("splash_pixel_size")), 0.003), "user tiny ripple size preset")
	verify(int(rain.get("max_simultaneous_splashes")) >= 100, "100 simultaneous ripples can be configured")
	verify(is_equal_approx(float(rain.get("splash_rate_per_second")), 80.0), "user splash rate preset")
	var frames: SpriteFrames = rain.get("_splash_frames") as SpriteFrames
	verify(frames != null, "original rain impact animations loaded")
	if frames != null:
		verify(frames.get_frame_count(&"ground") == 5, "ground ripple has five top-row frames")
		verify(frames.get_frame_count(&"water") == 5, "water ripple has five top-row frames")
		for name in [&"ground", &"water"]:
			for index in range(5):
				var region: Rect2 = (frames.get_frame_texture(name, index) as AtlasTexture).region
				verify(region.position.y == 3.0 and region.end.y <= 22.0 and region.size.x == 18.0, "only top row is used: %s frame %d" % [name, index])
	rain.call("_spawn_splash", Vector3.ZERO, &"water")
	verify(int(rain.call("get_active_splash_count")) == 1, "one-shot top-row water ripple spawns")
	var sprite: AnimatedSprite3D = rain.get_node_or_null("RainSplash") as AnimatedSprite3D
	if sprite != null:
		verify(is_equal_approx(sprite.pixel_size, 0.003), "tiny ripple scale is applied")
		verify(is_equal_approx(sprite.modulate.a, (171.0 / 255.0) * 0.38), "user splash color alpha and opacity are combined")
		rain.call("_recycle_splash", sprite)
		verify(int(rain.call("get_active_splash_count")) == 0, "completed ripple returns to pool")
	verify(not bool(rain.call("is_raining")), "clear weather does not emit rain")
	rain.set("weather_mode", 2)
	rain.call("_poll_weather")
	verify(bool(rain.call("is_raining")), "Rain Preview enables rainfall")
	if near != null and far != null:
		verify(near.emitting and far.emitting, "both layers emit in rain")
	rain.call("_follow_camera")
	if near != null and far != null:
		verify(near.global_position.distance_to(Vector3.ZERO) > 0.1, "rain follows the active camera")
		verify(near.global_basis.y.normalized().dot(camera.global_basis.y.normalized()) > 0.99, "near droplet Y axes are screen-vertical")
		verify(far.global_basis.y.normalized().dot(camera.global_basis.y.normalized()) > 0.99, "far droplet Y axes are screen-vertical")
		var near_box: Vector3 = (near.process_material as ParticleProcessMaterial).emission_box_extents
		verify(near_box.x > 0.1 and near_box.y < 0.01, "drops spawn in a thin band above the picture, not in the middle")
		verify(near_box.z < 0.1, "thin screen-parallel rain plane prevents world-space dilution")
		var viewport: Vector2 = root.get_visible_rect().size
		var above_picture: Vector3 = camera.project_position(Vector2(viewport.x * 0.5, 0.0), float(rain.get("rain_plane_distance")))
		verify(near.global_position.y > above_picture.y, "emitter is positioned above visible top for level-angle rain")
		verify(near.lifetime < 2.0, "drop lifetime matches a full frame traversal")
		var before_alpha: float = ((near.draw_pass_2 as QuadMesh).material as StandardMaterial3D).albedo_color.a
		rain.set("drop_opacity", 0.4)
		rain.call("_sync_rain_appearance")
		var after_alpha: float = ((near.draw_pass_2 as QuadMesh).material as StandardMaterial3D).albedo_color.a
		verify(after_alpha < before_alpha, "rain appearance updates from the live Inspector")
		rain.set("drop_opacity", 0.0)
		rain.call("_sync_rain_appearance")
		var edge_alpha: float = ((near.draw_pass_1 as QuadMesh).material as StandardMaterial3D).albedo_color.a
		var core_alpha: float = ((near.draw_pass_2 as QuadMesh).material as StandardMaterial3D).albedo_color.a
		verify(is_zero_approx(edge_alpha) and is_zero_approx(core_alpha), "zero opacity hides outline AND white drop")
		rain.set("drop_opacity", 0.7)
		rain.call("_sync_rain_appearance")
		rain.set("rain_plane_distance", 4.0)
		rain.call("_follow_camera")
		var new_height: float = camera.project_position(Vector2(viewport.x * 0.5, 0.0), 4.0).distance_to(camera.project_position(Vector2(viewport.x * 0.5, viewport.y), 4.0))
		var rain_process: ParticleProcessMaterial = near.process_material as ParticleProcessMaterial
		var normalized_speed: float = rain_process.initial_velocity_min / new_height
		verify(absf(normalized_speed - float(rain.get("drop_fall_speed")) * 0.94) < 0.02, "changing rain plane distance does not change apparent falling speed")
		rain.set("drop_angle_degrees", 25.0)
		rain.call("_follow_camera")
		verify(near.global_basis.y.normalized().dot(camera.global_basis.y.normalized()) < 0.96, "manual wind angle tilts entire streak and its fall")
		rain.set("drop_count", 300)
		rain.call("_sync_rain_appearance")
		verify(near.amount + far.amount == 300, "changing drop count updates active emitters")
	# Mesh-ray regression: test an uneven sea with NO physics collider.
	# Surface intersection must return the triangle height, not the node's origin Y.
	var fake_sea: MeshInstance3D = MeshInstance3D.new()
	var fake_mesh: ArrayMesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-2.0, -0.4, -2.0), Vector3(2.0, -0.6, -2.0), Vector3(2.0, -0.6, 2.0),
		Vector3(-2.0, -0.4, 2.0)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	fake_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	fake_sea.mesh = fake_mesh
	world.add_child(fake_sea)
	var actual_hit: Vector3 = rain.call("_mesh_ray_hit", Vector3.ZERO + Vector3(0.0, 4.0, 0.0), Vector3.DOWN, fake_sea, true)
	verify(actual_hit.x != INF and absf(actual_hit.y + 0.5) < 0.01, "water ripple ray hits actual sloped geometry")
	var void_hit: Vector3 = rain.call("_ground_intersection", Vector3(200.0, 10.0, 200.0), Vector3.DOWN)
	verify(void_hit.x == INF, "no splash is invented in void or on underwater floor")
	rain.set("weather_mode", 1)
	rain.call("_poll_weather")
	if near != null and far != null:
		verify(not near.emitting and not far.emitting, "all rain layers stop in clear weather")
	finish()

func finish() -> void:
	print("RAIN VISUAL V3 QA: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
