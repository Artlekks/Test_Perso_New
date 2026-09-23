extends Node3D

## Presentation-only 3-segment lure rig.
##
## The parent bait node still owns ALL real cast/sink/reel/fight movement.
## This rig only turns and positions three visual segments so they trail with
## progressively more delay, producing an articulated / snake-like motion.

@onready var segment_01: Node3D = $Segment01
@onready var segment_02: Node3D = $Segment02
@onready var segment_03: Node3D = $Segment03

@onready var segment_01_mesh: MeshInstance3D = $Segment01/Mesh
@onready var segment_02_mesh: MeshInstance3D = $Segment02/Mesh
@onready var segment_03_mesh: MeshInstance3D = $Segment03/Mesh

@export_category("Directional Response")
@export var motion_threshold: float = 0.015

## Head reacts fastest, tail reacts slowest.
@export var head_turn_speed: float = 14.0
@export var middle_turn_speed: float = 7.5
@export var tail_turn_speed: float = 4.5

## Even while moving, retain some influence from the fishing line so the lure
## still feels attached rather than behaving like a free projectile.
@export_range(0.0, 0.75, 0.05)
var line_alignment_weight: float = 0.20

@export_category("Chain Geometry")
## Total visible length stays close to the previous single-piece lure.
@export var segment_length: float = 0.058
@export var segment_gap: float = 0.003

@export_category("Surface Attitude")
## Close to the water surface, keep the whole articulated lure broadly flat.
@export_range(0.01, 1.0, 0.01)
var surface_flatten_depth: float = 0.15

## Small amount of pitch retained right at the surface.
@export_range(0.0, 0.75, 0.05)
var surface_vertical_influence: float = 0.10

@export_category("Underwater Attitude")
## Even when sinking/reeling vertically, keep the lure mostly horizontal,
## like a small submarine rather than a dart pointing straight down.
@export_range(0.0, 45.0, 1.0)
var max_underwater_pitch_degrees: float = 18.0

@export_category("Depth Readability")
## Presentation only. At this depth the lure reaches its full underwater fade.
## Slightly shorter than Pass 1 so the depth cue becomes obvious sooner.
@export_range(0.25, 8.0, 0.05)
var full_depth_visual_fade_distance: float = 2.35

## Lower than 1.0 makes the depth cue appear earlier; higher delays it.
@export_range(0.25, 2.5, 0.05)
var depth_visual_curve_power: float = 0.62

## Preserve the lure color authored in the bait scene/material at the surface.
## This prevents the readability system from replacing an orange/yellow lure with
## a hard-coded presentation color.
@export var preserve_material_surface_color: bool = true

## Used only when preserve_material_surface_color is disabled.
@export var surface_visual_color_override: Color = Color(1.0, 0.58, 0.10, 0.95)

## At maximum visual depth, darken the authored surface color toward black while
## keeping its hue family (orange stays dark orange rather than becoming blue).
@export_range(0.0, 0.95, 0.01)
var deep_darkening_amount: float = 0.72

## Extra alpha loss at maximum visual depth. Combined with the stronger darkening,
## this makes a deep lure visibly read as underwater without making it disappear.
@export_range(0.10, 1.0, 0.01)
var deep_alpha_multiplier: float = 0.48

var _bait: Node3D = null
var _visual_material: StandardMaterial3D = null
var _surface_base_color: Color = Color.WHITE
var _previous_world_position: Vector3 = Vector3.ZERO

var _head_direction: Vector3 = Vector3.FORWARD
var _middle_direction: Vector3 = Vector3.FORWARD
var _tail_direction: Vector3 = Vector3.FORWARD


func _ready() -> void:
	_bait = get_parent() as Node3D

	if _bait == null:
		set_physics_process(false)
		return

	_prepare_visual_material()
	_update_depth_readability()

	_previous_world_position = _bait.global_position

	var initial_direction := _get_line_direction()

	if initial_direction.length_squared() < 0.0001:
		initial_direction = Vector3.FORWARD

	initial_direction = _apply_surface_attitude(
		initial_direction,
		_bait.global_position
	)

	initial_direction = _limit_vertical_pitch(
		initial_direction
	)

	_head_direction = initial_direction.normalized()
	_middle_direction = _head_direction
	_tail_direction = _head_direction

	_place_chain()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_bait):
		return

	var current_world_position := _bait.global_position
	var world_motion := (
		current_world_position
		- _previous_world_position
	)
	_previous_world_position = current_world_position

	var desired_direction := Vector3.ZERO
	var movement_speed := (
		world_motion.length()
		/ maxf(delta, 0.0001)
	)

	var line_direction := _get_line_direction()

	if movement_speed >= motion_threshold:
		desired_direction = world_motion.normalized()

		if line_direction.length_squared() > 0.0001:
			desired_direction = (
				desired_direction
				* (1.0 - line_alignment_weight)
				+ line_direction
				* line_alignment_weight
			).normalized()
	elif line_direction.length_squared() > 0.0001:
		desired_direction = line_direction
	else:
		desired_direction = _head_direction

	if desired_direction.length_squared() < 0.0001:
		return

	desired_direction = _apply_surface_attitude(
		desired_direction,
		current_world_position
	)

	desired_direction = _limit_vertical_pitch(
		desired_direction
	)

	_head_direction = _follow_direction(
		_head_direction,
		desired_direction,
		head_turn_speed,
		delta
	)

	_middle_direction = _follow_direction(
		_middle_direction,
		_head_direction,
		middle_turn_speed,
		delta
	)

	_tail_direction = _follow_direction(
		_tail_direction,
		_middle_direction,
		tail_turn_speed,
		delta
	)

	_place_chain()
	_update_depth_readability()


func _prepare_visual_material() -> void:
	var source_material: Material = segment_01_mesh.get_active_material(0)

	if source_material is StandardMaterial3D:
		_visual_material = source_material.duplicate() as StandardMaterial3D
	else:
		_visual_material = StandardMaterial3D.new()
		_visual_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_visual_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# One duplicated material is intentionally shared by the three visual pieces
	# of THIS bait instance only. It cannot recolor other active baits/scenes.
	segment_01_mesh.set_surface_override_material(0, _visual_material)
	segment_02_mesh.set_surface_override_material(0, _visual_material)
	segment_03_mesh.set_surface_override_material(0, _visual_material)

	# Capture the authored lure color once. Depth presentation should modulate the
	# artist/user-selected color, never replace it with a hard-coded hue.
	if preserve_material_surface_color:
		_surface_base_color = _visual_material.albedo_color
	else:
		_surface_base_color = surface_visual_color_override


func _update_depth_readability() -> void:
	if _visual_material == null or not is_instance_valid(_bait):
		return

	if not _bait.has_method("get_water_surface_y"):
		_visual_material.albedo_color = _surface_base_color
		return

	var water_surface_y: float = float(_bait.get_water_surface_y())
	var depth_below_surface: float = maxf(
		water_surface_y - _bait.global_position.y,
		0.0
	)

	var normalized_depth: float = clampf(
		depth_below_surface / maxf(full_depth_visual_fade_distance, 0.001),
		0.0,
		1.0
	)

	var depth_blend: float = pow(
		normalized_depth,
		maxf(depth_visual_curve_power, 0.01)
	)

	var deep_color: Color = _surface_base_color.darkened(deep_darkening_amount)
	deep_color.a = _surface_base_color.a * deep_alpha_multiplier

	_visual_material.albedo_color = _surface_base_color.lerp(
		deep_color,
		depth_blend
	)


func _follow_direction(
	current: Vector3,
	target: Vector3,
	speed: float,
	delta: float
) -> Vector3:
	if target.length_squared() < 0.0001:
		return current

	if current.length_squared() < 0.0001:
		return target.normalized()

	var follow_weight := clampf(
		1.0 - exp(-speed * delta),
		0.0,
		1.0
	)

	return current.slerp(
		target.normalized(),
		follow_weight
	).normalized()


func _place_chain() -> void:
	if not is_instance_valid(_bait):
		return

	# Treat the bait's physical point as the line attachment at the FRONT of
	# segment 1. Every later segment is chained from the previous segment's tail.
	var joint_position := _bait.global_position

	joint_position = _place_segment(
		segment_01,
		joint_position,
		_head_direction
	)

	joint_position = _place_segment(
		segment_02,
		joint_position,
		_middle_direction
	)

	_place_segment(
		segment_03,
		joint_position,
		_tail_direction
	)


func _place_segment(
	segment: Node3D,
	front_joint: Vector3,
	direction: Vector3
) -> Vector3:
	if not is_instance_valid(segment):
		return front_joint

	var safe_direction := direction.normalized()
	var segment_basis := _basis_from_direction(safe_direction)

	# Local -Z is the wide/front end of each piece.
	# Therefore the segment center sits behind the front joint.
	var center := (
		front_joint
		- safe_direction
		* (segment_length * 0.5)
	)

	segment.global_transform = Transform3D(
		segment_basis,
		center
	)

	var tail_joint := (
		center
		- safe_direction
		* (segment_length * 0.5)
	)

	# Tiny separation makes the three-piece articulation readable.
	return (
		tail_joint
		- safe_direction
		* segment_gap
	)


func _basis_from_direction(direction: Vector3) -> Basis:
	var safe_up := Vector3.UP

	if absf(direction.dot(Vector3.UP)) > 0.96:
		safe_up = Vector3.FORWARD

	return Basis.looking_at(
		direction,
		safe_up
	).orthonormalized()


func _apply_surface_attitude(
	direction: Vector3,
	world_position: Vector3
) -> Vector3:
	if (
		_bait == null
		or not _bait.has_method("get_water_surface_y")
	):
		return direction.normalized()

	var water_y: float = float(
		_bait.get_water_surface_y()
	)

	var depth_below_surface := maxf(
		water_y - world_position.y,
		0.0
	)

	var depth_blend := clampf(
		depth_below_surface
		/ maxf(surface_flatten_depth, 0.001),
		0.0,
		1.0
	)

	if depth_blend >= 1.0:
		return direction.normalized()

	var horizontal := Vector3(
		direction.x,
		0.0,
		direction.z
	)

	if horizontal.length_squared() < 0.0001:
		var line_direction := _get_line_direction()
		horizontal = Vector3(
			line_direction.x,
			0.0,
			line_direction.z
		)

	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3(
			_head_direction.x,
			0.0,
			_head_direction.z
		)

	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3.FORWARD

	horizontal = horizontal.normalized()

	var surface_direction := (
		horizontal
		+ Vector3.UP
		* direction.y
		* surface_vertical_influence
	).normalized()

	return surface_direction.slerp(
		direction.normalized(),
		depth_blend
	).normalized()



func _limit_vertical_pitch(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.0001:
		return direction

	var normalized := direction.normalized()
	var horizontal := Vector3(
		normalized.x,
		0.0,
		normalized.z
	)

	# A pure vertical sink has no heading of its own. Borrow the line heading
	# so the lure can descend while still reading as a horizontal object.
	if horizontal.length_squared() < 0.0001:
		var line_direction := _get_line_direction()
		horizontal = Vector3(
			line_direction.x,
			0.0,
			line_direction.z
		)

	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3(
			_head_direction.x,
			0.0,
			_head_direction.z
		)

	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3.FORWARD

	horizontal = horizontal.normalized()

	var max_pitch_radians := deg_to_rad(
		clampf(
			max_underwater_pitch_degrees,
			0.0,
			89.0
		)
	)

	var requested_pitch := asin(
		clampf(
			normalized.y,
			-1.0,
			1.0
		)
	)

	var limited_pitch := clampf(
		requested_pitch,
		-max_pitch_radians,
		max_pitch_radians
	)

	var horizontal_scale := cos(limited_pitch)

	return (
		horizontal * horizontal_scale
		+ Vector3.UP * sin(limited_pitch)
	).normalized()


func _get_line_direction() -> Vector3:
	if _bait == null:
		return Vector3.ZERO

	if not _bait.has_method("get_reel_target_node"):
		return Vector3.ZERO

	var reel_target: Node3D = (
		_bait.get_reel_target_node()
		as Node3D
	)

	if not is_instance_valid(reel_target):
		return Vector3.ZERO

	var direction: Vector3 = (
		reel_target.global_position
		- _bait.global_position
	)

	if direction.length_squared() < 0.0001:
		return Vector3.ZERO

	return direction.normalized()
