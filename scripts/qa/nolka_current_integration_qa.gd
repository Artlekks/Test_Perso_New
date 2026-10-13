extends SceneTree
## Standalone Godot 4.7.2 regression: validates the ACTUAL purchased effect.
## Requires the full Nolka pack in the path declared by NolkaCurrentVisual.

const ViewScript = preload("res://scripts/fishing_current_surface_view.gd")
const BridgeScript = preload("res://scripts/environment_fx/nolka_current_visual.gd")
var checks: int = 0
var failed: Array[String] = []

class TestZone:
	extends Node
	var bounds: FishSwimBounds = null
	func get_swim_bounds() -> FishSwimBounds:
		return bounds
	func get_water_y() -> float:
		return 1.0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed.append(message)
		push_error("Nolka Current QA: " + message)

func run() -> void:
	var asset_path: String = BridgeScript.LEAVES_SCENE_PATH
	check(ResourceLoader.exists(asset_path, "PackedScene"), "complete purchased LeavesInWind scene installed: " + asset_path)
	if not ResourceLoader.exists(asset_path, "PackedScene"):
		print("Missing pack: copy the entire original nolkas_breeze_vfx_v1.0/nolkas_breeze folder into the FishingGame project.")
		_finish()
		return
	var scene: PackedScene = load(asset_path) as PackedScene
	check(scene != null, "Godot loads purchased PackedScene and dependencies")
	if scene == null:
		_finish()
		return
	var fishing: Node3D = Node3D.new()
	fishing.name = "TestFishing"
	root.add_child(fishing)
	var current: FishingCurrentService = FishingCurrentService.new()
	fishing.add_child(current)
	var spot: FishingSpotData = FishingSpotData.new()
	spot.current_speed = 0.25
	spot.current_direction = Vector2.RIGHT
	current.set_spot(spot)
	var bounds: FishSwimBounds = FishSwimBounds.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "BoundsShape3D"
	var cube: BoxShape3D = BoxShape3D.new()
	cube.size = Vector3(40.0, 5.0, 30.0)
	shape.shape = cube
	bounds.add_child(shape)
	fishing.add_child(bounds)
	current.set_swim_bounds(bounds)
	var zone: TestZone = TestZone.new()
	zone.bounds = bounds
	fishing.add_child(zone)
	var view: FishingCurrentSurfaceView = ViewScript.new() as FishingCurrentSurfaceView
	fishing.add_child(view)
	view.configure(current, null)
	view.bind_zone(zone)
	var bridge: Node3D = view.get_node_or_null("CurrentLines") as Node3D
	check(bridge != null, "new current adapter created")
	if bridge == null:
		_finish()
		return
	check(bool(bridge.call("has_effect")), "Nolka wind GPU effect is actually instantiated")
	var effect: Node3D = bridge.get_node_or_null("NolkaCurrentLines") as Node3D
	check(effect != null, "actual LeavesInWind root attached")
	if effect == null:
		_finish()
		return
	var wind: Node = effect.get_node_or_null("Wind")
	check(wind != null, "original NlkWindEmitter preserved")
	for name in ["OrangeLeaves", "GreenLeaves", "RedLeaves"]:
		check(not effect.has_node(NodePath(name)), "debris emitter removed: " + name)
	check(view._environment_overlay != null, "wind HUD and weather overlay preserved")
	check(view._drift_markers.size() == 6, "drift prediction markers preserved")
	var old_trails: int = 0
	for child in view.get_children():
		if str(child.name).begins_with("CurrentStreak"):
			old_trails += 1
	check(old_trails == 0, "no old procedural spaghetti trails instantiated")
	bridge.call("update_environment", current, bounds, 1.0, 0.1)
	check(effect.global_position.y > 1.0 and effect.global_position.y < 1.13, "thin visual layer hugs opaque water surface")
	var effect_area: Vector3 = effect.get("area")
	check(effect_area.x > 1.0 and effect_area.z > 1.0 and effect_area.y <= 0.08, "emission has water-wide XZ and shallow Y extent")
	if wind != null:
		check(int(wind.get("particles_amount")) == 46, "particle count uses tuned value, not composite default")
		var tint: Color = wind.get("color")
		check(tint.a < 0.4, "reduced underwater translucency")
		check(float(wind.get("sway_thickness")) < 0.2, "thinner moving lines")
	bridge.call("set_active", true)
	check(effect.visible, "emitter visible when active")
	if wind != null:
		check(bool(wind.get("emitting")), "original GPU emitter emitting when active")
	bridge.call("set_active", false)
	check(not effect.visible, "emitter invisible when inactive")
	if wind != null:
		check(not bool(wind.get("emitting")), "original GPU emitter stops emitting when inactive")
	# The bridge does not write back into the authoritative current simulation.
	check(current.get_snapshot().get("speed", 0.0) == spot.current_speed, "environment physics remains authoritative and unchanged")
	_finish()

func _finish() -> void:
	print("NOLKA CURRENT QA: %d checks, %d failed" % [checks, failed.size()])
	if failed.is_empty():
		print("NOLKA CURRENT QA PASSED")
		quit(0)
	else:
		quit(1)
