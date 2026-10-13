extends SceneTree
## Rain visual v3 regression: upright drops, top-row ripples only, no void splashes.
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
		verify(near.transform_align == GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD, "near raindrop quads face camera upright")
		verify(far.transform_align == GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD, "far raindrop quads face camera upright")
		var near_mesh: QuadMesh = near.draw_pass_1 as QuadMesh
		var far_mesh: QuadMesh = far.draw_pass_1 as QuadMesh
		verify(near_mesh != null and far_mesh != null, "both layers render quad meshes")
		if near_mesh != null and far_mesh != null:
			verify(near_mesh.size.y < 0.14 and near_mesh.size.x < 0.02, "rain mesh is small at game scale")
			verify(far_mesh.size.y < near_mesh.size.y, "distant streaks are shorter")
			var near_material: StandardMaterial3D = near_mesh.material as StandardMaterial3D
			var far_material: StandardMaterial3D = far_mesh.material as StandardMaterial3D
			verify(near_material != null and far_material != null, "both layers use textured transparent materials")
			if near_material != null and far_material != null:
				verify(near_material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED, "avoid double billboard rotation")
				verify(near_material.albedo_texture != null, "raindrop alpha-gradient texture exists")
				verify(near_material.albedo_color.b > near_material.albedo_color.r, "drops are pale blue, not grey")
				verify(far_material.albedo_color.a < near_material.albedo_color.a, "distant rain is less opaque")
	verify(ImpactAtlas.get_width() == 142 and ImpactAtlas.get_height() == 66, "original impact sheet preserved, only top row referenced")
	verify(is_equal_approx(float(rain.get("splash_pixel_size")), 0.005), "small ripple size preset")
	verify(int(rain.get("max_simultaneous_splashes")) >= 100, "100 simultaneous ripples can be configured")
	verify(float(rain.get("splash_rate_per_second")) >= 150.0, "splash spawn rate allows dozens concurrently")
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
		verify(is_equal_approx(sprite.pixel_size, 0.005), "tiny ripple scale is applied")
		verify(is_equal_approx(sprite.modulate.a, 0.8), "splash opacity is applied")
		rain.call("_recycle_splash", sprite)
		verify(int(rain.call("get_active_splash_count")) == 0, "completed ripple returns to pool")
	verify(not bool(rain.call("is_raining")), "clear weather does not emit rain")
	rain.set("weather_mode", 2)
	rain.call("_poll_weather")
	verify(bool(rain.call("is_raining")), "Rain Preview enables rainfall")
	if near != null and far != null:
		verify(near.emitting and far.emitting, "both layers emit in rain")
	rain.call("_follow_camera")
	if near != null:
		verify(near.global_position.distance_to(Vector3.ZERO) > 0.1, "rain follows the active camera")
	var void_hit: Vector3 = rain.call("_ground_intersection", Vector3(200.0, 10.0, 200.0), Vector3.DOWN)
	verify(void_hit.x == INF, "no splash is invented when no ground geometry exists")
	rain.set("weather_mode", 1)
	rain.call("_poll_weather")
	if near != null and far != null:
		verify(not near.emitting and not far.emitting, "all rain layers stop in clear weather")
	finish()

func finish() -> void:
	print("RAIN VISUAL V3 QA: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
