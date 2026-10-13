extends SceneTree
## Isolated logic/scene QA. Does not modify the project's wind simulation.
const WIND_SCENE = preload("res://actors/FishingWindVFX.tscn")
const WIND_SERVICE = preload("res://scripts/world/game_wind_service.gd")

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("NOLKA WIND QA: " + message)

func run() -> void:
	var world: Node3D = Node3D.new()
	world.name = "World"
	root.add_child(world)
	var beach: Node3D = Node3D.new()
	beach.name = "beach"
	world.add_child(beach)
	var sea: MeshInstance3D = MeshInstance3D.new()
	sea.name = "Sea"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(20.0, 0.1, 12.0)
	sea.mesh = mesh
	beach.add_child(sea)

	var wind_vfx: Node3D = WIND_SCENE.instantiate() as Node3D
	check(wind_vfx != null, "wind scene instantiates")
	if wind_vfx == null:
		finish()
		return
	wind_vfx.name = "FishingWindVFX"
	world.add_child(wind_vfx)
	var vendor: Node3D = wind_vfx.get_node_or_null("NolkaWindLines") as Node3D
	check(vendor != null, "original Nolka Breeze is instanced")
	if vendor == null:
		finish()
		return
	check(vendor.get_node_or_null("SwayEmitter") is GPUParticles3D, "original particle emitter is present")
	check(absf(float(wind_vfx.get("opacity")) - 0.18) < 0.001, "subtle wind opacity saved")
	check(not bool(wind_vfx.call("is_wind_display_running")), "starts inactive until valid wind snapshot")

	var authoritative: Node = WIND_SERVICE.new()
	var source_snapshot: Dictionary = authoritative.call("get_snapshot_at_minutes", 480) as Dictionary
	check(bool(source_snapshot.get("available", false)), "uses real wind-service snapshots")
	wind_vfx.call("_update_from_snapshot", source_snapshot)
	check(bool(wind_vfx.call("is_wind_display_running")), "actual GameWind data drives emitter")
	wind_vfx.call("_update_from_snapshot", {"available": true, "speed_mps": 1.5, "velocity_xz": Vector2(1.5, 0.0)})
	check(bool(wind_vfx.call("is_wind_display_running")), "wind lines emit with wind")
	var slow: float = float(vendor.get("speed_scale"))
	var area: Vector3 = vendor.get("area")
	check(area.x >= 6.0 and area.z >= 6.0 and area.y > 0.5, "wind volume is spatially bounded")
	check(vendor.global_basis.z.dot(Vector3.RIGHT) > 0.99, "wind travels in service's +X direction")
	wind_vfx.call("_update_from_snapshot", {"available": true, "speed_mps": 6.0, "velocity_xz": Vector2(0.0, -6.0)})
	var fast: float = float(vendor.get("speed_scale"))
	check(fast > slow, "higher wind speed makes effect faster")
	check(vendor.global_basis.z.dot(Vector3.FORWARD) > 0.99, "wind rotates with direction")
	wind_vfx.call("_update_from_snapshot", {"available": true, "speed_mps": 0.0, "velocity_xz": Vector2.ZERO})
	check(not bool(wind_vfx.call("is_wind_display_running")), "calm air disables wind effect")
	wind_vfx.call("_update_from_snapshot", {"available": false})
	check(not bool(wind_vfx.call("is_wind_display_running")), "missing wind never invents a direction")
	check(world.get_node_or_null("FishingCurrentVFX") == null, "wind QA does not modify the current effect")
	finish()

func finish() -> void:
	print("NOLKA WIND V1 QA: %d checks, %d failed" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
