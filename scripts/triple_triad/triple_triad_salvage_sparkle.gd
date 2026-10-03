extends Node3D
class_name TripleTriadSalvageSparkle

## Lightweight prototype marker for an authored fishing-salvage target.
## It owns presentation only. The fishing salvage bridge decides when it appears
## and whether the player's cast is close enough to arm the recovery.

@export var trigger_radius: float = 1.0
@export var bob_height: float = 0.08
@export var bob_speed: float = 3.0
@export var pulse_speed: float = 4.0

var _base_position: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0
var _visual_root: Node3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_visual()
	_base_position = position
	set_process(true)


func configure(world_position: Vector3, radius: float = 1.0) -> void:
	trigger_radius = maxf(0.25, radius)
	global_position = world_position
	_base_position = position


func is_cast_near(world_point: Vector3) -> bool:
	var marker_flat := Vector2(global_position.x, global_position.z)
	var cast_flat := Vector2(world_point.x, world_point.z)
	return marker_flat.distance_to(cast_flat) <= trigger_radius


func get_debug_snapshot() -> Dictionary:
	return {
		"world_position": global_position,
		"trigger_radius": trigger_radius,
		"visible": visible,
	}


func _process(delta: float) -> void:
	_elapsed += delta
	position.y = _base_position.y + sin(_elapsed * bob_speed) * bob_height
	rotation.y += delta * 1.4
	if is_instance_valid(_visual_root):
		var pulse := 1.0 + sin(_elapsed * pulse_speed) * 0.16
		_visual_root.scale = Vector3.ONE * pulse


func _build_visual() -> void:
	if is_instance_valid(_visual_root):
		return

	_visual_root = Node3D.new()
	_visual_root.name = "SparkleVisual"
	add_child(_visual_root)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.93, 0.58, 0.95)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.88, 0.38, 1.0)
	material.emission_energy_multiplier = 3.0

	var offsets := [
		Vector3.ZERO,
		Vector3(0.11, 0.02, 0.0),
		Vector3(-0.11, -0.01, 0.0),
		Vector3(0.0, 0.04, 0.11),
		Vector3(0.0, -0.02, -0.11),
	]
	for index in range(offsets.size()):
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Spark%d" % index
		var sphere := SphereMesh.new()
		sphere.radius = 0.045 if index > 0 else 0.07
		sphere.height = 0.09 if index > 0 else 0.14
		mesh_instance.mesh = sphere
		mesh_instance.material_override = material
		mesh_instance.position = offsets[index]
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual_root.add_child(mesh_instance)

	var light := OmniLight3D.new()
	light.name = "SparkleLight"
	light.light_color = Color(1.0, 0.86, 0.42, 1.0)
	light.light_energy = 1.15
	light.omni_range = 1.6
	light.shadow_enabled = false
	_visual_root.add_child(light)
