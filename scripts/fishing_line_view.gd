extends Node3D

## Presentation-only fishing line.
##
## The line follows the animated rod-tip tracker and the real bait root.
## Once the lure is underwater it is split at the actual water-plane entry,
## so the player can read rod -> surface entry -> submerged bait.
##
## This pass intentionally uses a small procedural curve instead of rope
## physics. The line remains responsive and cheap, but no longer reads as a
## perfectly rigid laser. Fast bait movement pulls the line more taut while
## slower/static moments allow a little sag and sway.
##
## No fishing mechanics depend on this node.

@export_category("References")
@export var caster: Node
@export var rod_tip: Node3D

@export_category("Line Look")
@export var above_water_color: Color = Color(0.92, 0.90, 0.76, 0.82)
@export var underwater_color: Color = Color(0.54, 0.66, 0.67, 0.42)

@export_range(0.05, 1.0, 0.01)
var deep_underwater_alpha_multiplier: float = 0.48

@export_range(0.25, 8.0, 0.05)
var full_underwater_line_fade_depth: float = 3.0

## Tiny lift to keep the surface split from fighting the water plane visually.
@export_range(0.0, 0.08, 0.001)
var surface_epsilon: float = 0.018

@export_category("Line Curve")
## Low segment counts keep the curve a little angular/pixel-friendly rather
## than turning it into a modern smooth rope.
@export_range(2, 12, 1)
var curve_segments: int = 6

## Base sag on the section above the water.
@export_range(0.0, 0.30, 0.005)
var above_water_sag: float = 0.075

## Extra sag added on long casts. This is multiplied by line length and capped.
@export_range(0.0, 0.08, 0.001)
var sag_per_world_unit: float = 0.010

@export_range(0.0, 0.40, 0.005)
var max_above_water_sag: float = 0.18

## Small sideways movement keeps the line alive even when the bait is still.
@export_range(0.0, 0.08, 0.001)
var line_sway_amplitude: float = 0.016

@export_range(0.1, 6.0, 0.05)
var line_sway_speed: float = 1.35

## Underwater line stays tighter than the aerial section, but gets a subtle bow.
@export_range(0.0, 0.15, 0.005)
var underwater_bow: float = 0.035

## Bait speed at which the line is considered strongly tensioned visually.
## Even then a small amount of curvature remains.
@export_range(0.1, 12.0, 0.1)
var taut_speed_reference: float = 3.0

@export_range(0.0, 1.0, 0.05)
var minimum_curve_when_taut: float = 0.30

var _above_mesh: ImmediateMesh
var _underwater_mesh: ImmediateMesh
var _above_instance: MeshInstance3D
var _underwater_instance: MeshInstance3D
var _above_material: StandardMaterial3D
var _underwater_material: StandardMaterial3D

var _surface_entry_position: Vector3 = Vector3.ZERO
var _has_surface_entry: bool = false

var _line_time: float = 0.0
var _previous_bait_position: Vector3 = Vector3.ZERO
var _has_previous_bait_position: bool = false

# Hook Off / Line Break keep the bait alive briefly for the failure presentation.
# Hide the line for that specific bait instead of letting a frozen line remain
# on-screen through the broken-line animation/result transition.
var _hidden_for_failed_fight: bool = false
var _hidden_bait_instance_id: int = -1


func _ready() -> void:
	process_priority = 110
	_build_runtime_meshes()
	_connect_failure_signals()
	_clear_line()


func _process(delta: float) -> void:
	_line_time += delta

	if not is_instance_valid(caster) or not is_instance_valid(rod_tip):
		_reset_motion_history()
		_clear_line()
		return

	var bait: Node3D = caster.get("active_bait") as Node3D

	if not is_instance_valid(bait):
		_hidden_for_failed_fight = false
		_hidden_bait_instance_id = -1
		_reset_motion_history()
		_clear_line()
		return

	# A failed fight intentionally keeps the frozen bait around while the Hook Off
	# / Line Break presentation plays. Keep the line hidden for that same bait,
	# but automatically restore it as soon as a brand-new cast creates a new bait.
	if _hidden_for_failed_fight:
		var bait_instance_id: int = bait.get_instance_id()
		if bait_instance_id == _hidden_bait_instance_id:
			_clear_line()
			return

		_hidden_for_failed_fight = false
		_hidden_bait_instance_id = -1
		_reset_motion_history()

	var rod_position: Vector3 = rod_tip.global_position
	var bait_position: Vector3 = bait.global_position
	var water_y: float = bait_position.y

	if bait.has_method("get_water_surface_y"):
		water_y = float(bait.call("get_water_surface_y")) + surface_epsilon

	var bait_speed: float = _measure_bait_speed(bait_position, delta)
	_update_line(rod_position, bait_position, water_y, bait_speed)


func _connect_failure_signals() -> void:
	# Keep this view self-contained: Encounter is the sibling that owns the
	# authoritative Hook Off / Line Break events in the active Fishing scene.
	var encounter_node: Node = get_node_or_null("../Encounter")
	if encounter_node == null:
		return

	if encounter_node.has_signal("hook_off"):
		encounter_node.connect("hook_off", _on_failed_fight_line)

	if encounter_node.has_signal("line_broken"):
		encounter_node.connect("line_broken", _on_failed_fight_line)


func _on_failed_fight_line() -> void:
	_hidden_for_failed_fight = true
	_hidden_bait_instance_id = -1

	if is_instance_valid(caster):
		var bait: Node3D = caster.get("active_bait") as Node3D
		if is_instance_valid(bait):
			_hidden_bait_instance_id = bait.get_instance_id()

	_reset_motion_history()
	_clear_line()


func get_surface_entry_position() -> Vector3:
	return _surface_entry_position


func has_surface_entry() -> bool:
	return _has_surface_entry


func _build_runtime_meshes() -> void:
	_above_mesh = ImmediateMesh.new()
	_underwater_mesh = ImmediateMesh.new()

	_above_material = _make_line_material(above_water_color)
	_underwater_material = _make_line_material(underwater_color)

	_above_instance = MeshInstance3D.new()
	_above_instance.name = "AboveWaterLine"
	_above_instance.mesh = _above_mesh
	_above_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_above_instance.extra_cull_margin = 64.0
	add_child(_above_instance)

	_underwater_instance = MeshInstance3D.new()
	_underwater_instance.name = "UnderwaterLine"
	_underwater_instance.mesh = _underwater_mesh
	_underwater_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_underwater_instance.extra_cull_margin = 64.0
	add_child(_underwater_instance)


func _make_line_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = color
	return material


func _update_line(
	rod_position: Vector3,
	bait_position: Vector3,
	water_y: float,
	bait_speed: float
) -> void:
	_has_surface_entry = false

	var taut_ratio: float = clampf(
		bait_speed / maxf(taut_speed_reference, 0.001),
		0.0,
		1.0
	)
	var curve_multiplier: float = lerpf(
		1.0,
		minimum_curve_when_taut,
		taut_ratio
	)

	# While the bait is airborne, draw a single curved line from rod to lure.
	if bait_position.y >= water_y:
		_draw_curved_segment(
			_above_mesh,
			_above_material,
			rod_position,
			bait_position,
			_calculate_above_sag(rod_position, bait_position) * curve_multiplier,
			line_sway_amplitude * curve_multiplier,
			0.0
		)
		_underwater_mesh.clear_surfaces()
		return

	var entry_position: Vector3 = _calculate_water_intersection(
		rod_position,
		bait_position,
		water_y
	)

	_surface_entry_position = entry_position
	_has_surface_entry = true

	_draw_curved_segment(
		_above_mesh,
		_above_material,
		rod_position,
		entry_position,
		_calculate_above_sag(rod_position, entry_position) * curve_multiplier,
		line_sway_amplitude * curve_multiplier,
		0.0
	)

	var depth: float = maxf(water_y - bait_position.y, 0.0)
	var depth_ratio: float = clampf(
		depth / maxf(full_underwater_line_fade_depth, 0.001),
		0.0,
		1.0
	)
	var alpha_multiplier: float = lerpf(
		1.0,
		deep_underwater_alpha_multiplier,
		depth_ratio
	)
	var submerged_color: Color = underwater_color
	submerged_color.a *= alpha_multiplier
	_underwater_material.albedo_color = submerged_color

	_draw_curved_segment(
		_underwater_mesh,
		_underwater_material,
		entry_position,
		bait_position,
		underwater_bow * curve_multiplier,
		line_sway_amplitude * 0.45 * curve_multiplier,
		PI * 0.65
	)


func _calculate_above_sag(start: Vector3, end: Vector3) -> float:
	var distance: float = start.distance_to(end)
	return minf(
		above_water_sag + distance * sag_per_world_unit,
		max_above_water_sag
	)


func _draw_curved_segment(
	mesh: ImmediateMesh,
	material: Material,
	world_start: Vector3,
	world_end: Vector3,
	sag_amount: float,
	sway_amount: float,
	phase_offset: float
) -> void:
	mesh.clear_surfaces()

	if world_start.distance_squared_to(world_end) <= 0.000001:
		return

	var line_direction: Vector3 = world_end - world_start
	var horizontal_direction := Vector3(line_direction.x, 0.0, line_direction.z)
	var sideways := Vector3.ZERO

	if horizontal_direction.length_squared() > 0.000001:
		horizontal_direction = horizontal_direction.normalized()
		sideways = Vector3.UP.cross(horizontal_direction).normalized()

	var midpoint: Vector3 = world_start.lerp(world_end, 0.5)
	var sway: float = sin(_line_time * line_sway_speed + phase_offset) * sway_amount
	var control: Vector3 = midpoint + Vector3.DOWN * sag_amount + sideways * sway

	var segment_count: int = maxi(curve_segments, 2)
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)

	for index in range(segment_count + 1):
		var t: float = float(index) / float(segment_count)
		var inverse_t: float = 1.0 - t
		var point: Vector3 = (
			inverse_t * inverse_t * world_start
			+ 2.0 * inverse_t * t * control
			+ t * t * world_end
		)
		mesh.surface_add_vertex(to_local(point))

	mesh.surface_end()


func _calculate_water_intersection(
	rod_position: Vector3,
	bait_position: Vector3,
	water_y: float
) -> Vector3:
	var vertical_delta: float = bait_position.y - rod_position.y

	if absf(vertical_delta) > 0.00001:
		var t: float = (water_y - rod_position.y) / vertical_delta

		if t >= 0.0 and t <= 1.0:
			var intersection: Vector3 = rod_position.lerp(bait_position, t)
			intersection.y = water_y
			return intersection

	# If camera/framing ever puts the rod-tip proxy on the wrong side of the water
	# plane, keep the line readable by falling back to the same bait-head
	# projection used by the surface feedback system.
	if caster.has_method("get_active_bait_visual_surface_position"):
		var fallback: Vector3 = caster.call(
			"get_active_bait_visual_surface_position"
		)
		fallback.y = water_y
		return fallback

	return Vector3(bait_position.x, water_y, bait_position.z)


func _measure_bait_speed(bait_position: Vector3, delta: float) -> float:
	if not _has_previous_bait_position or delta <= 0.000001:
		_previous_bait_position = bait_position
		_has_previous_bait_position = true
		return 0.0

	var speed: float = bait_position.distance_to(_previous_bait_position) / delta
	_previous_bait_position = bait_position
	return speed


func _reset_motion_history() -> void:
	_has_previous_bait_position = false
	_previous_bait_position = Vector3.ZERO


func _clear_line() -> void:
	_has_surface_entry = false

	if _above_mesh != null:
		_above_mesh.clear_surfaces()

	if _underwater_mesh != null:
		_underwater_mesh.clear_surfaces()
