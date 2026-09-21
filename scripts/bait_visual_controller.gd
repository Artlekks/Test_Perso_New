extends Node3D

## Presentation-only orientation controller for the bait mesh.
##
## The parent Bait node still owns all actual cast/sink/reel/fight movement.
## This node only reads that motion and rotates a replaceable 3D visual.

@export_category("Directional Response")
@export var turn_speed: float = 10.0
@export var motion_threshold: float = 0.015

## Even while the lure is moving, retain a little influence from the fishing
## line so the object feels attached instead of behaving like a free projectile.
@export_range(0.0, 0.75, 0.05)
var line_alignment_weight: float = 0.20

@export_category("Surface Attitude")
## While the lure is within this distance below the water surface, progressively
## bias it toward a horizontal posture. Once deeper than this, normal 3D
## orientation takes over completely.
@export_range(0.01, 1.0, 0.01)
var surface_flatten_depth: float = 0.15

## How much vertical pitch remains exactly at the surface.
## 0.0 = perfectly horizontal, 0.20 = a small visible dip.
@export_range(0.0, 0.75, 0.05)
var surface_vertical_influence: float = 0.18

var _bait: Node3D = null
var _previous_world_position: Vector3 = Vector3.ZERO
var _smoothed_direction: Vector3 = Vector3.FORWARD


func _ready() -> void:
	_bait = get_parent() as Node3D

	if _bait == null:
		set_physics_process(false)
		return

	_previous_world_position = _bait.global_position

	var initial_direction := _get_line_direction()

	if initial_direction.length_squared() < 0.0001:
		initial_direction = Vector3.FORWARD

	initial_direction = _apply_surface_attitude(
		initial_direction,
		_bait.global_position
	)

	_smoothed_direction = initial_direction.normalized()
	_apply_direction(_smoothed_direction)


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
		# At rest, hang naturally along the fishing line.
		desired_direction = line_direction
	else:
		desired_direction = Vector3.DOWN

	if desired_direction.length_squared() < 0.0001:
		return

	desired_direction = _apply_surface_attitude(
		desired_direction,
		current_world_position
	)

	var follow_weight := clampf(
		1.0 - exp(-turn_speed * delta),
		0.0,
		1.0
	)

	_smoothed_direction = _smoothed_direction.slerp(
		desired_direction.normalized(),
		follow_weight
	).normalized()

	_apply_direction(_smoothed_direction)



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

	# Once sufficiently underwater, allow the full 3D movement direction.
	if depth_blend >= 1.0:
		return direction.normalized()

	var horizontal := Vector3(
		direction.x,
		0.0,
		direction.z
	)

	# Pure sink/rise motion has no horizontal component. At the surface we still
	# want a lure-shaped object to lie along the fishing line rather than stand
	# vertically, so borrow the line's horizontal heading.
	if horizontal.length_squared() < 0.0001:
		var line_direction := _get_line_direction()
		horizontal = Vector3(
			line_direction.x,
			0.0,
			line_direction.z
		)

	# Final fallback: preserve whichever horizontal heading we were already using.
	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3(
			_smoothed_direction.x,
			0.0,
			_smoothed_direction.z
		)

	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3.FORWARD

	horizontal = horizontal.normalized()

	# A small amount of the requested vertical movement remains visible at the
	# surface, giving a slight dip/rise instead of locking the lure dead-flat.
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


func _apply_direction(direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		return

	# Basis.looking_at points local -Z along the requested direction.
	# In the scene, the WIDE end of the placeholder lure is rotated toward -Z,
	# so the body/front leads and the pointed end reads as the tail.
	var safe_up := Vector3.UP

	if absf(direction.dot(Vector3.UP)) > 0.96:
		safe_up = Vector3.FORWARD

	global_basis = Basis.looking_at(
		direction,
		safe_up
	).orthonormalized()
