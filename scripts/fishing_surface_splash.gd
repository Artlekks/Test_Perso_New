extends Node3D

## Temporary procedural presentation for the two surface-splash events.
## Replace the visuals later; callers only depend on configure().

@export var landing_lifetime: float = 0.42
@export var fight_lifetime: float = 0.58
@export var ring_inner_radius: float = 0.075
@export var ring_outer_radius: float = 0.095
@export var surface_offset: float = 0.018

var _strength: float = 1.0
var _fight_variant: bool = false
var _age: float = 0.0
var _lifetime: float = 0.5
var _configured: bool = false

var _ring: MeshInstance3D = null
var _ring_material: StandardMaterial3D = null
var _droplets: Array[MeshInstance3D] = []
var _drop_velocities: Array[Vector3] = []
var _drop_start_positions: Array[Vector3] = []


func _ready() -> void:
	top_level = true
	set_process(false)


func configure(
	world_position: Vector3,
	strength: float,
	fight_variant: bool
) -> void:
	global_position = world_position + Vector3.UP * surface_offset
	_strength = maxf(strength, 0.05)
	_fight_variant = fight_variant
	_lifetime = fight_lifetime if fight_variant else landing_lifetime
	_build_placeholder()
	_configured = true
	set_process(true)


func _build_placeholder() -> void:
	_build_ring()
	_build_droplets()


func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "SurfaceRing"

	var torus := TorusMesh.new()
	var size_scale := _strength * (1.10 if _fight_variant else 0.72)
	torus.inner_radius = ring_inner_radius * size_scale
	torus.outer_radius = ring_outer_radius * size_scale
	torus.rings = 16
	torus.ring_segments = 24
	_ring.mesh = torus

	_ring_material = _make_material(0.72 if _fight_variant else 0.58)
	_ring.material_override = _ring_material
	add_child(_ring)
	_ring.scale = Vector3.ONE * 0.45


func _build_droplets() -> void:
	var count := 7 if _fight_variant else 4
	var spread := 0.22 * _strength * (1.25 if _fight_variant else 0.72)
	var launch_height := 0.75 * _strength * (1.25 if _fight_variant else 0.72)

	for i in range(count):
		var drop := MeshInstance3D.new()
		drop.name = "Drop_%02d" % i

		var sphere := SphereMesh.new()
		sphere.radius = 0.022 * _strength
		sphere.height = 0.085 * _strength
		sphere.radial_segments = 6
		sphere.rings = 3
		drop.mesh = sphere
		drop.material_override = _make_material(
			0.82 if _fight_variant else 0.68
		)
		add_child(drop)

		var angle := TAU * (float(i) / float(maxi(count, 1)))
		angle += randf_range(-0.25, 0.25)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var start := direction * randf_range(0.01, 0.035) * _strength
		drop.position = start

		_droplets.append(drop)
		_drop_start_positions.append(start)
		_drop_velocities.append(
			direction * randf_range(spread * 0.55, spread)
			+ Vector3.UP * randf_range(launch_height * 0.75, launch_height)
		)


func _process(delta: float) -> void:
	if not _configured:
		return

	_age += delta
	var t := clampf(_age / maxf(_lifetime, 0.01), 0.0, 1.0)
	_update_ring(t)
	_update_droplets(t)

	if t >= 1.0:
		queue_free()


func _update_ring(t: float) -> void:
	if not is_instance_valid(_ring):
		return

	var growth := lerpf(0.45, 2.4 if _fight_variant else 1.65, t)
	_ring.scale = Vector3.ONE * growth

	if _ring_material != null:
		var color := _ring_material.albedo_color
		color.a = (1.0 - t) * (0.70 if _fight_variant else 0.55)
		_ring_material.albedo_color = color


func _update_droplets(t: float) -> void:
	var gravity := 2.8 * _strength
	var elapsed := t * _lifetime

	for i in range(_droplets.size()):
		var drop := _droplets[i]
		if not is_instance_valid(drop):
			continue

		var velocity := _drop_velocities[i]
		var position := (
			_drop_start_positions[i]
			+ velocity * elapsed
			+ Vector3.DOWN * 0.5 * gravity * elapsed * elapsed
		)

		# Placeholder droplets never render below the surface plane.
		position.y = maxf(position.y, 0.0)
		drop.position = position
		drop.scale = Vector3.ONE * maxf(1.0 - t * 0.70, 0.25)

		var material := drop.material_override as StandardMaterial3D
		if material != null:
			var color := material.albedo_color
			color.a = (1.0 - t) * (0.80 if _fight_variant else 0.65)
			material.albedo_color = color


func _make_material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.72, 0.90, 1.0, alpha)
	return material
