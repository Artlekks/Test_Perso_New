extends Node3D

## Temporary procedural presentation for the two surface-splash events.
## Replace this scene/script later with the cleaned BOF4 sprite animation.
## Gameplay callers only depend on configure().

@export_category("Timing")
@export var landing_lifetime: float = 0.46
@export var fight_lifetime: float = 0.54
@export_range(4.0, 30.0, 1.0)
var placeholder_animation_fps: float = 12.0

@export_category("Ring")
@export var ring_inner_radius: float = 0.075
@export var ring_outer_radius: float = 0.095
@export_range(0.2, 2.0, 0.05)
var landing_ring_size_multiplier: float = 1.05
@export_range(0.2, 2.0, 0.05)
var fight_ring_size_multiplier: float = 0.74
@export var surface_offset: float = 0.018

@export_category("Landing Jet")
@export var landing_jet_count: int = 2
@export_range(0.02, 0.5, 0.01)
var landing_jet_height: float = 0.205
@export_range(0.005, 0.08, 0.005)
var landing_jet_radius: float = 0.014

var _strength: float = 1.0
var _fight_variant: bool = false
var _age: float = 0.0
var _lifetime: float = 0.5
var _configured: bool = false

# Fight-only visual anchor. A hooked bait may be metres below the surface, but
# the splash must remain on the surface while sharing the bait head's screen
# position. Tracking for the brief splash lifetime prevents visible drift.
var _follow_target: Node3D = null
var _follow_surface_y: float = 0.0

var _ring: MeshInstance3D = null
var _ring_material: StandardMaterial3D = null
var _droplets: Array[MeshInstance3D] = []
var _drop_velocities: Array[Vector3] = []
var _drop_start_positions: Array[Vector3] = []
var _jets: Array[MeshInstance3D] = []
var _jet_offsets: Array[Vector3] = []


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


func set_follow_target(target: Node3D) -> void:
	if not is_instance_valid(target):
		_follow_target = null
		return

	_follow_target = target
	_follow_surface_y = global_position.y - surface_offset
	_update_follow_anchor()


func _update_follow_anchor() -> void:
	if not _fight_variant or not is_instance_valid(_follow_target):
		return

	var bait_position: Vector3 = _follow_target.global_position
	var surface_y: float = _follow_surface_y

	# Prefer the lure's real water height if available. This keeps the effect
	# robust if a future fishing spot uses a different water elevation.
	if _follow_target.has_method("get_water_surface_y"):
		surface_y = float(_follow_target.get_water_surface_y()) + 0.025

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		global_position = Vector3(
			bait_position.x,
			surface_y + surface_offset,
			bait_position.z
		)
		return

	var screen_position: Vector2 = camera.unproject_position(bait_position)
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)

	if absf(ray_direction.y) <= 0.00001:
		return

	var distance_along_ray: float = (surface_y - ray_origin.y) / ray_direction.y
	if distance_along_ray < 0.0:
		return

	var projected: Vector3 = ray_origin + ray_direction * distance_along_ray
	projected.y = surface_y + surface_offset
	global_position = projected


func _build_placeholder() -> void:
	_build_ring()
	_build_droplets()

	if not _fight_variant:
		_build_landing_jets()


func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "SurfaceRing"

	var torus := TorusMesh.new()
	var variant_scale := (
		fight_ring_size_multiplier
		if _fight_variant
		else landing_ring_size_multiplier
	)
	var size_scale := _strength * variant_scale
	torus.inner_radius = ring_inner_radius * size_scale
	torus.outer_radius = ring_outer_radius * size_scale

	# Low segment counts intentionally keep the temporary effect chunky rather
	# than looking like a smooth modern particle effect beside the pixel art.
	torus.rings = 8
	torus.ring_segments = 12
	_ring.mesh = torus

	_ring_material = _make_material(0.70 if _fight_variant else 0.62)
	_ring.material_override = _ring_material
	add_child(_ring)
	_ring.scale = Vector3.ONE * 0.45


func _build_droplets() -> void:
	var count := 5 if _fight_variant else 4
	var spread := 0.22 * _strength * (0.92 if _fight_variant else 0.78)
	var launch_height := 0.75 * _strength * (0.92 if _fight_variant else 0.72)

	for i in range(count):
		var drop := MeshInstance3D.new()
		drop.name = "Drop_%02d" % i

		var sphere := SphereMesh.new()
		sphere.radius = 0.020 * _strength
		sphere.height = 0.075 * _strength
		sphere.radial_segments = 4
		sphere.rings = 2
		drop.mesh = sphere
		drop.material_override = _make_material(
			0.80 if _fight_variant else 0.72
		)
		add_child(drop)

		var angle := TAU * (float(i) / float(maxi(count, 1)))
		angle += randf_range(-0.22, 0.22)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var start := direction * randf_range(0.01, 0.03) * _strength
		drop.position = start

		_droplets.append(drop)
		_drop_start_positions.append(start)
		_drop_velocities.append(
			direction * randf_range(spread * 0.55, spread)
			+ Vector3.UP * randf_range(launch_height * 0.72, launch_height)
		)


func _build_landing_jets() -> void:
	var count := maxi(landing_jet_count, 0)

	for i in range(count):
		var jet := MeshInstance3D.new()
		jet.name = "LandingJet_%02d" % i

		var sphere := SphereMesh.new()
		sphere.radius = landing_jet_radius * _strength
		sphere.height = landing_jet_height * _strength
		sphere.radial_segments = 4
		sphere.rings = 2
		jet.mesh = sphere
		jet.material_override = _make_material(0.78)

		var side := -1.0 if i % 2 == 0 else 1.0
		var offset := Vector3(
			side * 0.018 * _strength,
			0.0,
			randf_range(-0.012, 0.012) * _strength
		)
		jet.position = offset
		add_child(jet)

		_jets.append(jet)
		_jet_offsets.append(offset)


func _process(delta: float) -> void:
	if not _configured:
		return

	# Keep fight splashes glued to the bait head's screen-space location for the
	# full effect lifetime. Landing splashes intentionally remain where they hit.
	_update_follow_anchor()

	_age += delta
	var raw_t := clampf(_age / maxf(_lifetime, 0.01), 0.0, 1.0)
	var t := _quantize_progress(raw_t)

	_update_ring(t)
	_update_droplets(t)
	_update_landing_jets(t)

	if raw_t >= 1.0:
		queue_free()


func _quantize_progress(value: float) -> float:
	if placeholder_animation_fps <= 0.0:
		return value

	var frame_count := maxf(_lifetime * placeholder_animation_fps, 1.0)
	return clampf(
		floor(value * frame_count) / frame_count,
		0.0,
		1.0
	)


func _update_ring(t: float) -> void:
	if not is_instance_valid(_ring):
		return

	var end_scale := 2.10 if _fight_variant else 1.90
	var growth := lerpf(0.45, end_scale, t)
	_ring.scale = Vector3.ONE * growth

	if _ring_material != null:
		var color := _ring_material.albedo_color
		color.a = (1.0 - t) * (0.68 if _fight_variant else 0.60)
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

		position.y = maxf(position.y, 0.0)
		drop.position = position
		drop.scale = Vector3.ONE * maxf(1.0 - t * 0.70, 0.25)

		var material := drop.material_override as StandardMaterial3D
		if material != null:
			var color := material.albedo_color
			color.a = (1.0 - t) * (0.78 if _fight_variant else 0.68)
			material.albedo_color = color


func _update_landing_jets(t: float) -> void:
	if _fight_variant:
		return

	# A tiny near-vertical spout on water entry. It rises quickly, then collapses
	# back into the surface. This is only a timing/shape placeholder for the
	# eventual BOF4 sprite animation.
	var arc := sin(clampf(t, 0.0, 1.0) * PI)

	for i in range(_jets.size()):
		var jet := _jets[i]
		if not is_instance_valid(jet):
			continue

		var base := _jet_offsets[i]
		jet.position = base + Vector3.UP * arc * landing_jet_height * 0.42 * _strength
		jet.scale = Vector3(
			maxf(1.0 - t * 0.45, 0.45),
			maxf(arc, 0.08),
			maxf(1.0 - t * 0.45, 0.45)
		)

		var material := jet.material_override as StandardMaterial3D
		if material != null:
			var color := material.albedo_color
			color.a = (1.0 - t) * 0.76
			material.albedo_color = color


func _make_material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.72, 0.90, 1.0, alpha)
	return material
