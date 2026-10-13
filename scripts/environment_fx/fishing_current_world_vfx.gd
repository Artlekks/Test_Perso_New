extends Node3D
## World-owned presentation of the installed Nolka LeavesInWind preset.
## Physics and fish behavior stay exclusively in FishingCurrentService.
## The vendor scene and its shader are not modified.

@export_category("World Binding")
@export var zone_path: NodePath = ^"../FishZone_V2"
@export var fishing_controller_path: NodePath = ^"../../Game/Fishing"
@export var sea_mesh_path: NodePath = ^"../beach/Sea"
@export var display_current: bool = true
@export var reverse_flow_direction: bool = false

@export_category("Nolka Current - Size")
## All original Nolka motion dimensions are reduced by the same ratio.
## This preserves the relative curve shape instead of creating giant ribbons.
@export_range(0.12, 0.5, 0.01) var visual_scale: float = 0.22
## Duration of a trail in Nolka's animation. With scale 0.22 and the
## default speed range, a complete ribbon spans about 0.8-1.5 world units.
@export_range(0.25, 2.0, 0.05) var trail_duration: float = 0.75
@export_range(0.05, 1.0, 0.01) var opacity: float = 0.36
@export_range(8, 160, 1) var particles: int = 54
## Thickness, speed, and turbulence below are the ORIGINAL Nolka units.
## Visual Scale reduces all of them before they reach the particle system.
@export_range(0.05, 0.5, 0.01) var reference_line_width: float = 0.20
@export_range(5.0, 20.0, 0.5) var reference_min_speed: float = 5.0
@export_range(5.0, 25.0, 0.5) var reference_max_speed: float = 9.0

@export_category("Nolka Current - Curves")
@export_range(0.0, 10.0, 0.1) var reference_min_turbulence: float = 2.0
@export_range(0.0, 15.0, 0.1) var reference_max_turbulence: float = 5.0
@export_range(0.005, 0.03, 0.001) var reference_noise_domain: float = 0.008
## Short lines need more noise variation per metre to show clear curves.
@export_range(1.0, 5.0, 0.1) var curvature_detail: float = 2.5

@export_category("Nolka Current - Coverage")
## The sea mesh, not the much smaller FishSwimBounds, sets coverage.
@export_range(0.25, 1.0, 0.05) var sea_coverage: float = 0.80
@export_range(0.2, 1.5, 0.05) var playback_speed: float = 0.80

@export_category("Underwater Appearance")
@export var submerge_lines: bool = true
@export_range(0.005, 0.15, 0.005) var below_water_depth: float = 0.035
@export_range(0.005, 0.2, 0.005) var above_water_offset: float = 0.055
@export_range(0.60, 1.0, 0.01) var water_surface_opacity: float = 0.80

const SAMPLE_PERIOD: float = 1.0 / 12.0

var _elapsed: float = 0.0
var _nolka: Node3D = null
var _wind: Node = null
var _zone: Node = null
var _sea_mesh: MeshInstance3D = null
var _sea_original_material: Material = null
var _sea_current_material: ShaderMaterial = null
var _last_visual_settings: Array = []

func _enter_tree() -> void:
	# Remove debris before Nolka's composite caches its children in _ready().
	var effect: Node = get_node_or_null("NolkaCurrentLines")
	if effect != null:
		for leaf_name in ["OrangeLeaves", "GreenLeaves", "RedLeaves"]:
			var leaf: Node = effect.get_node_or_null(NodePath(leaf_name))
			if leaf != null:
				effect.remove_child(leaf)
				leaf.free()

func _ready() -> void:
	_nolka = get_node_or_null("NolkaCurrentLines") as Node3D
	if _nolka == null:
		push_error("FishingCurrentVFX: missing NolkaCurrentLines instance.")
		set_process(false)
		return
	_wind = _nolka.get_node_or_null("Wind")
	if _wind == null:
		push_error("FishingCurrentVFX: missing purchased Wind emitter.")
		set_process(false)
		return
	_apply_appearance()
	_set_emitting(false)
	set_process(true)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < SAMPLE_PERIOD:
		return
	_elapsed = 0.0
	_update_flow()

func _current_zone() -> Node:
	if not is_instance_valid(_zone):
		_zone = get_node_or_null(zone_path)
	return _zone

func _find_sea() -> MeshInstance3D:
	if not is_instance_valid(_sea_mesh):
		_sea_mesh = get_node_or_null(sea_mesh_path) as MeshInstance3D
	return _sea_mesh

func _sea_world_corners() -> Array[Vector3]:
	var corners: Array[Vector3] = []
	var sea: MeshInstance3D = _find_sea()
	if sea == null or sea.mesh == null:
		return corners
	var box: AABB = sea.get_aabb()
	var low: Vector3 = box.position
	var high: Vector3 = box.end
	var middle_y: float = box.get_center().y
	for x in [low.x, high.x]:
		for z in [low.z, high.z]:
			corners.append(sea.to_global(Vector3(x, middle_y, z)))
	return corners

func _get_coverage(heading: Vector3, fallback_bounds: FishSwimBounds, water_y: float) -> Dictionary:
	var corners: Array[Vector3] = _sea_world_corners()
	if corners.is_empty():
		# QA and locations without a Sea mesh retain the safe fishing bounds.
		if fallback_bounds == null:
			return {}
		for uv in [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0)]:
			corners.append(fallback_bounds.normalized_uv_to_world(uv, water_y))
	var across: Vector3 = Vector3(-heading.z, 0.0, heading.x)
	var first: Vector3 = corners[0]
	var min_across: float = first.dot(across)
	var max_across: float = min_across
	var min_forward: float = first.dot(heading)
	var max_forward: float = min_forward
	for point in corners:
		var across_coordinate: float = point.dot(across)
		var forward_coordinate: float = point.dot(heading)
		min_across = minf(min_across, across_coordinate)
		max_across = maxf(max_across, across_coordinate)
		min_forward = minf(min_forward, forward_coordinate)
		max_forward = maxf(max_forward, forward_coordinate)
	var center: Vector3 = across * ((min_across + max_across) * 0.5) + heading * ((min_forward + max_forward) * 0.5)
	center.y = water_y
	var width: float = maxf((max_across - min_across) * sea_coverage, 0.5)
	var length: float = maxf((max_forward - min_forward) * sea_coverage, 0.5)
	return {"center": center, "area": Vector3(width, 0.025, length)}

func _update_flow() -> void:
	if _nolka == null or _wind == null:
		return
	if not display_current:
		_set_emitting(false)
		return
	var zone: Node = _current_zone()
	if zone == null or not zone.has_method("get_fishing_spot") or not zone.has_method("get_swim_bounds") or not zone.has_method("get_water_y"):
		_set_emitting(false)
		return
	var spot: FishingSpotData = zone.call("get_fishing_spot") as FishingSpotData
	var bounds: FishSwimBounds = zone.call("get_swim_bounds") as FishSwimBounds
	if spot == null or bounds == null:
		_set_emitting(false)
		return
	var controller: Node = get_node_or_null(fishing_controller_path)
	var service: FishingCurrentService = null
	if controller != null:
		service = controller.get("fishing_current_service") as FishingCurrentService
	if service == null:
		_set_emitting(false)
		return
	# Spot sampling works both during exploration and active fishing.
	var sampled_flow: Vector2 = service.sample_spot_at_uv(spot, Vector2(0.5, 0.5))
	var flow: Vector3 = Vector3(sampled_flow.x, 0.0, sampled_flow.y)
	if flow.length_squared() <= 0.000001:
		_set_emitting(false)
		return
	var heading: Vector3 = flow.normalized()
	if reverse_flow_direction:
		heading = -heading
	var water_y: float = float(zone.call("get_water_y"))
	var coverage_info: Dictionary = _get_coverage(heading, bounds, water_y)
	if coverage_info.is_empty():
		_set_emitting(false)
		return
	var center: Vector3 = coverage_info["center"]
	var area: Vector3 = coverage_info["area"]
	var visual_height: float = water_y - below_water_depth if submerge_lines else water_y + above_water_offset
	_nolka.global_position = Vector3(center.x, visual_height, center.z)
	# Nolka's shader travels along +Z, whereas Godot looking_at faces -Z.
	_nolka.global_basis = Basis.looking_at(-heading, Vector3.UP)
	var previous_area: Vector3 = _nolka.get("area")
	if not previous_area.is_equal_approx(area):
		_nolka.set("area", area)
	_apply_appearance()
	var speed_factor: float = clampf(flow.length() / 0.25, 0.75, 1.25)
	var target_speed: float = clampf(playback_speed * speed_factor, 0.2, 1.5)
	if absf(float(_nolka.get("speed_scale")) - target_speed) > 0.015:
		_nolka.set("speed_scale", target_speed)
	_set_emitting(true)

func _apply_appearance() -> void:
	if _wind == null:
		return
	# Nolka's min_speed setter clamps values below 1.0. A visual_scale
	# below 0.20 would silently flatten its original speed variation.
	var effective_min_speed: float = maxf(1.0, reference_min_speed * visual_scale)
	var effective_max_speed: float = maxf(effective_min_speed, reference_max_speed * visual_scale)
	var effective_domain: float = reference_noise_domain / visual_scale * curvature_detail
	var settings: Array = [visual_scale, trail_duration, opacity, particles, reference_line_width, reference_min_speed, reference_max_speed, reference_min_turbulence, reference_max_turbulence, reference_noise_domain, curvature_detail]
	if settings == _last_visual_settings:
		return
	_last_visual_settings = settings.duplicate()
	_wind.set("sway_thickness", reference_line_width * visual_scale)
	_wind.set("sway_duration", trail_duration)
	_wind.set("color", Color(0.73, 0.88, 0.94, opacity))
	# Nolka clamps min_speed to its existing max_speed. Lower min first,
	# then max, or reducing both from the vendor defaults cannot work.
	_wind.set("min_speed", effective_min_speed)
	_wind.set("max_speed", effective_max_speed)
	_wind.set("min_turbulence_amplitude", reference_min_turbulence * visual_scale)
	_wind.set("max_turbulence_amplitude", maxf(reference_max_turbulence, reference_min_turbulence) * visual_scale)
	_wind.set("turbulence_domain_scale", effective_domain)
	_wind.set("particles_amount", particles)
	var gpu: GPUParticles3D = _wind.get_node_or_null("SwayEmitter") as GPUParticles3D
	if gpu != null:
		# The vendor sets a very thin visibility AABB for our shallow area.
		# Turbulent particles can move beyond it; a cull margin avoids popping.
		gpu.extra_cull_margin = 2.0

func _set_emitting(active: bool) -> void:
	if _nolka != null:
		_nolka.visible = active
		if bool(_nolka.get("emitting")) != active:
			_nolka.set("emitting", active)
	if _wind != null and bool(_wind.get("emitting")) != active:
		_wind.set("emitting", active)
	_update_water_surface(active and submerge_lines)

func _update_water_surface(active: bool) -> void:
	var sea: MeshInstance3D = _find_sea()
	if sea == null:
		return
	if not active:
		if _sea_current_material != null and sea.material_override == _sea_current_material:
			sea.material_override = _sea_original_material
		return
	if _sea_current_material == null:
		var base: ShaderMaterial = sea.material_override as ShaderMaterial
		if base == null:
			return
		_sea_original_material = base
		_sea_current_material = base.duplicate() as ShaderMaterial
		if _sea_current_material == null:
			return
		_sea_current_material.render_priority = 1
	if sea.material_override != _sea_current_material:
		sea.material_override = _sea_current_material
	_sea_current_material.set_shader_parameter("current_water_opacity", water_surface_opacity)

func _exit_tree() -> void:
	if is_instance_valid(_sea_mesh) and _sea_current_material != null:
		if _sea_mesh.material_override == _sea_current_material:
			_sea_mesh.material_override = _sea_original_material

func is_current_display_running() -> bool:
	return _nolka != null and _nolka.visible and _wind != null and bool(_wind.get("emitting"))
