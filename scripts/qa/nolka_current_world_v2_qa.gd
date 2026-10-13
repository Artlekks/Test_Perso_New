extends SceneTree
## FRESH4 VFX regression. Uses the INSTALLED Nolka scene and a wide fake sea.
const WorldVfx = preload("res://actors/FishingCurrentVFX.tscn")

var checks: int = 0
var failures: Array[String] = []

class FakeZone:
	extends Node3D
	var spot: FishingSpotData = null
	var bounds: FishSwimBounds = null
	func get_fishing_spot() -> FishingSpotData:
		return spot
	func get_swim_bounds() -> FishSwimBounds:
		return bounds
	func get_water_y() -> float:
		return 0.0

class FakeFishing:
	extends Node
	var fishing_current_service: FishingCurrentService = null

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("NOLKA CURRENT VFX QA: " + message)

func run() -> void:
	var root_scene: Node3D = Node3D.new()
	root_scene.name = "FishingTestScene_V2"
	root.add_child(root_scene)
	var world: Node3D = Node3D.new()
	world.name = "World"
	root_scene.add_child(world)
	var game: Node3D = Node3D.new()
	game.name = "Game"
	root_scene.add_child(game)
	var fishing: FakeFishing = FakeFishing.new()
	fishing.name = "Fishing"
	game.add_child(fishing)
	var service: FishingCurrentService = FishingCurrentService.new()
	fishing.add_child(service)
	fishing.fishing_current_service = service
	var spot: FishingSpotData = FishingSpotData.new()
	spot.current_speed = 0.25
	spot.current_direction = Vector2.RIGHT
	var zone: FakeZone = FakeZone.new()
	zone.name = "FishZone_V2"
	zone.spot = spot
	world.add_child(zone)
	var bounds: FishSwimBounds = FishSwimBounds.new()
	bounds.name = "FishSwimBounds"
	var box_shape: CollisionShape3D = CollisionShape3D.new()
	box_shape.name = "BoundsShape3D"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(3.5, 1.0, 1.5)
	box_shape.shape = box
	bounds.add_child(box_shape)
	world.add_child(bounds)
	zone.bounds = bounds

	var beach: Node3D = Node3D.new()
	beach.name = "beach"
	world.add_child(beach)
	var sea: MeshInstance3D = MeshInstance3D.new()
	sea.name = "Sea"
	var sea_shape: BoxMesh = BoxMesh.new()
	sea_shape.size = Vector3(30.0, 0.02, 16.0)
	sea.mesh = sea_shape
	var original_material: ShaderMaterial = ShaderMaterial.new()
	original_material.shader = load("res://assets/models/shaders/sea_far_fade.gdshader") as Shader
	sea.material_override = original_material
	beach.add_child(sea)

	var vfx: Node3D = WorldVfx.instantiate() as Node3D
	check(vfx != null, "authored scene instantiates")
	if vfx == null:
		_finish()
		return
	vfx.name = "FishingCurrentVFX"
	world.add_child(vfx)
	var nolka: Node3D = vfx.get_node_or_null("NolkaCurrentLines") as Node3D
	check(nolka != null, "installed Nolka scene remains instanced")
	if nolka == null:
		_finish()
		return
	for name in ["OrangeLeaves", "GreenLeaves", "RedLeaves"]:
		check(not nolka.has_node(NodePath(name)), "debris emitter removed: " + name)
	var wind: Node = nolka.get_node_or_null("Wind")
	check(wind != null, "Nolka wind controller retained")
	if wind == null:
		_finish()
		return
	var particles: GPUParticles3D = wind.get_node_or_null("SwayEmitter") as GPUParticles3D
	check(particles != null, "original GPU emitter retained")
	vfx.call("_update_flow")
	check(bool(vfx.call("is_current_display_running")), "current emits during exploration")
	check(not bool(service.get_snapshot().get("active", false)), "no fishing session required")

	var scale: float = float(vfx.get("visual_scale"))
	var min_speed: float = float(wind.get("min_speed"))
	var max_speed: float = float(wind.get("max_speed"))
	var duration: float = float(wind.get("sway_duration"))
	check(absf(min_speed - 5.0 * scale) < 0.02, "Nolka minimum speed scaled")
	check(absf(max_speed - 9.0 * scale) < 0.02, "Nolka maximum speed scaled")
	check(max_speed * duration < 1.7, "trail length stays within character-scale range")
	check(absf(float(wind.get("sway_thickness")) - 0.20 * scale) < 0.01, "ribbon width scales with motion")
	check(absf(float(wind.get("min_turbulence_amplitude")) - 2.0 * scale) < 0.01, "minimum sway amplitude scales")
	check(absf(float(wind.get("max_turbulence_amplitude")) - 5.0 * scale) < 0.01, "maximum sway amplitude scales")
	check(float(wind.get("turbulence_domain_scale")) > 0.08, "short trails have sufficient curvature detail")
	var tint: Color = wind.get("color")
	check(tint.a < 0.5, "subtle line opacity")
	if particles != null:
		check(particles.extra_cull_margin >= 1.5, "animated curvature has particle culling margin")

	var volume: Vector3 = nolka.get("area")
	check(maxf(volume.x, volume.z) > 10.0, "visual coverage uses whole sea rather than small fishing bounds")
	check(volume.y < 0.08, "emission volume is shallow")
	check(nolka.global_position.y < 0.0, "effect starts below water surface")
	var flow: Vector2 = service.sample_spot_at_uv(spot, Vector2(0.5, 0.5))
	var flow3: Vector3 = Vector3(flow.x, 0.0, flow.y).normalized()
	check(nolka.global_basis.z.dot(flow3) > 0.99, "Nolka +Z particle velocity matches live current heading")
	check(sea.material_override != original_material, "instance-only water opacity override")
	var transparent: ShaderMaterial = sea.material_override as ShaderMaterial
	check(transparent != null, "sea retains shader material")
	if transparent != null:
		check(absf(float(transparent.get_shader_parameter("current_water_opacity")) - 0.80) < 0.001, "sea opacity remains configurable")
	vfx.set("display_current", false)
	vfx.call("_update_flow")
	check(not bool(vfx.call("is_current_display_running")), "visual off switch disables emission")
	check(sea.material_override == original_material, "sea material restored when effect disabled")
	check(not bool(service.get_snapshot().get("active", false)), "effect never starts or alters fishing session")
	_finish()

func _finish() -> void:
	print("NOLKA FRESH4 VFX QA: %d checks, %d failed" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
